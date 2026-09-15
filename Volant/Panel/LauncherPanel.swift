import AppKit
import SwiftUI
import OSLog

/// A floating, non-activating, borderless panel that hosts the SwiftUI launcher and toggles on the summon hotkey.
final class LauncherPanel: NSPanel, NSWindowDelegate {
    static var scale: Double = 1.0
    static var opacity: Double = 1.0
    static var size: NSSize { NSSize(width: 750 * scale, height: 480 * scale) }
    let model: LauncherModel
    private let positionStore: UserDefaults
    private var restoringPosition = false
    let snapGuides = LauncherSnapGuides()

    init(index: AppIndex, clipboard: ClipboardStore, notes: NotesStore, config: Preferences, usage: UsageStore = UsageStore(), positionStore: UserDefaults = .standard, onNote: @escaping (LauncherAction) -> Void) {
        self.positionStore = positionStore
        LauncherPanel.scale = min(1.4, max(0.8, config.appearance.scale))
        LauncherPanel.opacity = min(1.0, max(0.5, config.appearance.opacity))
        model = LauncherModel(index: index, clipboard: clipboard, notes: notes, config: config, usage: usage, onNote: onNote)
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
        model.wifiJoin != nil || model.connectivityBusy
    }

    override func resignKey() {
        super.resignKey()
        if !PermissionGate.isPrompting && !keepsVisibleOnBlur { orderOut(nil) }
    }

    func toggle() {
        if let modal = NSApp.modalWindow {
            if isVisible { orderOut(nil) }
            modal.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        if isVisible {
            if isKeyWindow { orderOut(nil) }
            else { makeKeyAndOrderFront(nil) }
            return
        }
        model.isPresented = true
        if !keepsVisibleOnBlur { model.reset() }
        model.resumeAgentsIfNeeded()
        restorePositionOrCenter()
        makeKeyAndOrderFront(nil)
        contentView?.layoutSubtreeIfNeeded()
        if let field = searchInput(in: contentView) {
            makeFirstResponder(field)
        } else {
            model.searchFocusRequest = UUID()
        }
        DispatchQueue.main.async { [weak self] in
            guard let self, self.isVisible, !self.isKeyWindow else { return }
            Logger(subsystem: "com.mysticcoders.volant", category: "Launcher").fault("Launcher failed to become key; dismissing instead of leaving an unresponsive panel.")
            self.orderOut(nil)
        }
    }

    private func searchInput(in view: NSView?) -> NSTextField? {
        guard let view else { return nil }
        if let field = view as? NSTextField, field.placeholderString == "Search for apps, files, contacts, or calculate…" { return field }
        return view.subviews.lazy.compactMap { self.searchInput(in: $0) }.first
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
        endDragging()
        model.isPresented = false
        model.agents.disconnect()
        super.orderOut(sender)
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

    override func cancelOperation(_ sender: Any?) { orderOut(nil) }
}

private extension NSSize {
    var area: CGFloat { max(0, width) * max(0, height) }
}
