import AppKit
import SwiftUI
import OSLog

/// A floating, non-activating, borderless panel that hosts the SwiftUI launcher and toggles on the summon hotkey.
final class LauncherPanel: NSPanel, NSWindowDelegate {
    private static let openingLog = OSLog(subsystem: "com.mysticcoders.volant", category: "Opening")
    static var scale: Double = 1.0
    static var opacity: Double = 1.0
    static var size: NSSize { NSSize(width: 750 * scale, height: 480 * scale) }
    let model: LauncherModel
    private let positionStore: UserDefaults
    private var restoringPosition = false
    private let preparesWhenHidden: Bool
    private var hiddenPreparation: DispatchWorkItem?
    private var presentationGeneration = 0
    let snapGuides = LauncherSnapGuides()

    init(index: AppIndex, clipboard: ClipboardStore, notes: NotesStore, config: Preferences, usage: UsageStore = UsageStore(), positionStore: UserDefaults = .standard, caffeinate: CaffeinateService = CaffeinateService(), preparesWhenHidden: Bool = true, onNote: @escaping (LauncherAction) -> Void) {
        self.positionStore = positionStore
        self.preparesWhenHidden = preparesWhenHidden
        LauncherPanel.scale = min(1.4, max(0.8, config.appearance.scale))
        LauncherPanel.opacity = min(1.0, max(0.5, config.appearance.opacity))
        model = LauncherModel(index: index, clipboard: clipboard, notes: notes, config: config, usage: usage, caffeinate: caffeinate, onNote: onNote)
        super.init(contentRect: NSRect(origin: .zero, size: LauncherPanel.size),
                   styleMask: [.nonactivatingPanel, .borderless, .fullSizeContentView],
                   backing: .buffered, defer: false)
        delegate = self
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        isMovableByWindowBackground = true
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        isReleasedWhenClosed = false
        hidesOnDeactivate = false
        model.dismiss = { [weak self] in self?.orderOut(nil) }
        contentView = NSHostingView(rootView: LauncherView(model: model, agents: model.agents)
            .background(Color(nsColor: .windowBackgroundColor), in: RoundedRectangle(cornerRadius: 14)))
    }

    override var canBecomeKey: Bool { true }

    /// Ordinary search is transient; conversations and unfinished input survive focus changes.
    var keepsVisibleOnBlur: Bool {
        model.acp.active || model.acp.submitting ||
        (model.showingACP && !model.acp.draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) ||
        model.wifiJoin != nil || model.connectivityBusy ||
        (model.showingTranslation && model.translation.hasDraft)
    }

    override func resignKey() {
        super.resignKey()
        if !PermissionGate.isPrompting && !keepsVisibleOnBlur { orderOut(nil) }
    }

    func toggle(source: LauncherOpenSource = .other, requestedAt: TimeInterval? = nil) {
        let started = requestedAt ?? ProcessInfo.processInfo.systemUptime
        hiddenPreparation?.cancel(); hiddenPreparation = nil
        presentationGeneration += 1
        let generation = presentationGeneration
        if let modal = NSApp.modalWindow {
            if isVisible { orderOut(nil) }
            modal.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        if isVisible {
            if isKeyWindow { orderOut(nil) }
            else {
                let trace = LauncherOpeningTrace(source: source, started: started)
                makeKeyAndOrderFront(nil)
                trace.finish(ready: isKeyWindow && firstResponder is NSTextView)
            }
            return
        }
        let trace = LauncherOpeningTrace(source: source, started: started)
        let openingID = OSSignpostID(log: Self.openingLog)
        os_signpost(.begin, log: Self.openingLog, name: "Prepare launcher", signpostID: openingID)
        let previousQuery = model.query
        let previousSections = model.sections
        let previousSelection = model.selection
        model.isPresented = true
        if !keepsVisibleOnBlur { model.reset() }
        model.resumeAgentsIfNeeded()
        restorePositionOrCenter()
        os_signpost(.end, log: Self.openingLog, name: "Prepare launcher", signpostID: openingID)
        os_signpost(.begin, log: Self.openingLog, name: "Present and focus", signpostID: openingID)
        makeKeyAndOrderFront(nil)
        os_signpost(.event, log: Self.openingLog, name: "Window ordered", signpostID: openingID)
        // Reuse only an unchanged ordinary search surface. A matching editor alone
        // is insufficient: emoji mode, result changes, or selection changes also
        // need layout before showing the new state.
        let existingInput = searchInput(in: contentView)
        let displayedText = existingInput?.currentEditor()?.string ?? existingInput?.stringValue
        let unchangedSearch = model.query.isEmpty && previousQuery == model.query &&
            previousSections == model.sections && previousSelection == model.selection
        if !unchangedSearch || existingInput == nil || displayedText != model.searchText {
            os_signpost(.begin, log: Self.openingLog, name: "Required layout", signpostID: openingID)
            contentView?.layoutSubtreeIfNeeded()
            os_signpost(.end, log: Self.openingLog, name: "Required layout", signpostID: openingID)
        }
        os_signpost(.event, log: Self.openingLog, name: "Search editor ready", signpostID: openingID)
        if let field = searchInput(in: contentView) {
            makeFirstResponder(field)
        } else {
            model.searchFocusRequest = UUID()
        }
        os_signpost(.end, log: Self.openingLog, name: "Present and focus", signpostID: openingID)
        let ready = isKeyWindow && firstResponder is NSTextView
        if ready { trace.finish(ready: true) }
        DispatchQueue.main.async { [weak self] in
            guard let self, self.isVisible, self.presentationGeneration == generation else {
                trace.finish(ready: false)
                return
            }
            guard self.isKeyWindow else {
                trace.finish(ready: false)
                Logger(subsystem: "com.mysticcoders.volant", category: "Launcher").fault("Launcher failed to become key; dismissing instead of leaving an unresponsive panel.")
                self.orderOut(nil)
                return
            }
            // SwiftUI can finish installing its focus state after the initial native focus.
            // Reconcile once after layout, without interrupting an existing text editor.
            if !(self.firstResponder is NSTextView), let field = self.searchInput(in: self.contentView) {
                self.makeFirstResponder(field)
            }
            trace.finish(ready: self.firstResponder is NSTextView)
        }
    }

    private func searchInput(in view: NSView?) -> NSTextField? {
        guard let view else { return nil }
        if let field = view as? NSTextField, ["Search for apps, files, contacts, or calculate…", "Search emoji…"].contains(field.placeholderString ?? "") { return field }
        return view.subviews.lazy.compactMap { self.searchInput(in: $0) }.first
    }

    func showEmoji() {
        if NSApp.modalWindow != nil { toggle(); return }
        if !isVisible { toggle() } else { makeKeyAndOrderFront(nil) }
        guard isVisible else { return }
        model.query = ":"
        model.searchFocusRequest = UUID()
    }

    func showAgents() {
        if !isVisible { toggle() }
        model.query = "agents"
        makeKeyAndOrderFront(nil)
    }

    func drag(to origin: NSPoint, pointer: NSPoint, freely: Bool) {
        let proposed = NSRect(origin: origin, size: frame.size)
        guard !freely, let screen = NSScreen.screens.first(where: { $0.frame.contains(pointer) }) ?? self.screen else {
            snapGuides.hide()
            setFrameOrigin(origin)
            return
        }
        let placement = LauncherSnapPlacement.resolve(proposed, in: screen.visibleFrame)
        setFrameOrigin(placement.frame.origin)
        snapGuides.show(placement, screen: screen.visibleFrame, above: self)
    }

    func endDragging() { snapGuides.hide() }

    override func orderOut(_ sender: Any?) {
        hiddenPreparation?.cancel(); hiddenPreparation = nil
        presentationGeneration += 1
        endDragging()
        model.dictionary.clear()
        model.actionTarget = nil
        model.isPresented = false
        model.agents.disconnect()
        super.orderOut(sender)
        guard preparesWhenHidden, !keepsVisibleOnBlur else { return }
        let generation = presentationGeneration
        let dismissedQuery = model.query
        let preparation = DispatchWorkItem { [weak self] in
            guard let self, self.presentationGeneration == generation else { return }
            self.hiddenPreparation = nil
            guard !self.isVisible, !self.keepsVisibleOnBlur, self.model.query == dismissedQuery,
                  NSApp.modalWindow == nil else { return }
            let id = OSSignpostID(log: Self.openingLog)
            os_signpost(.begin, log: Self.openingLog, name: "Prepare hidden home", signpostID: id)
            self.model.reset()
            self.contentView?.layoutSubtreeIfNeeded()
            os_signpost(.end, log: Self.openingLog, name: "Prepare hidden home", signpostID: id)
        }
        hiddenPreparation = preparation
        // One cancellable idle task, not a repeating timer. Rapid reopens use normal reset.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1, execute: preparation)
    }

    func windowDidMove(_ notification: Notification) {
        guard isVisible, !restoringPosition else { return }
        positionStore.set(["x": frame.origin.x, "y": frame.origin.y], forKey: "launcherPosition")
    }

    private func restorePositionOrCenter() {
        restoringPosition = true
        defer { restoringPosition = false }
        let screens = NSScreen.screens.map(\.visibleFrame)
        let mouse = NSEvent.mouseLocation
        let fallback = screens.first { $0.contains(mouse) } ?? NSScreen.main?.visibleFrame
        guard let fallback else { return }
        if let saved = positionStore.dictionary(forKey: "launcherPosition"),
           let x = saved["x"] as? Double, let y = saved["y"] as? Double, x.isFinite, y.isFinite {
            let proposed = NSRect(origin: NSPoint(x: x, y: y), size: frame.size)
            let screen = screens.max {
                $0.intersection(proposed).size.area < $1.intersection(proposed).size.area
            }.flatMap { $0.intersects(proposed) ? $0 : nil } ?? fallback
            setFrameOrigin(NSPoint(x: min(max(x, screen.minX), max(screen.minX, screen.maxX - frame.width)),
                                   y: min(max(y, screen.minY), max(screen.minY, screen.maxY - frame.height))))
        } else {
            setFrameOrigin(NSPoint(x: fallback.midX - frame.width / 2,
                                   y: fallback.midY - frame.height / 2 + fallback.height * 0.10))
        }
    }

    /// Development aid for screenshots: `Volant --show --query saf`.
    func setQuery(_ text: String) { model.query = text }

    func apply(config: Preferences) { model.config = config }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        let modifiers = event.modifierFlags.intersection([.command, .control, .option, .shift])
        if modifiers == .command, event.charactersIgnoringModifiers?.lowercased() == "k",
           model.selectedRow?.supportsActions == true {
            model.toggleActions()
            if model.actionTarget == nil { model.searchFocusRequest = UUID() }
            return true
        }
        return super.performKeyEquivalent(with: event)
    }

    override func cancelOperation(_ sender: Any?) {
        if model.actionTarget != nil { model.actionTarget = nil; model.searchFocusRequest = UUID() }
        else { orderOut(nil) }
    }
}

private extension NSSize {
    var area: CGFloat { max(0, width) * max(0, height) }
}
