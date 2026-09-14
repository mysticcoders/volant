import AppKit
import SwiftUI
import OSLog

/// A floating, non-activating, borderless panel that hosts the SwiftUI launcher and toggles on the summon hotkey.
final class LauncherPanel: NSPanel {
    static var scale: Double = 1.0
    static var opacity: Double = 1.0
    static var size: NSSize { NSSize(width: 750 * scale, height: 480 * scale) }
    let model: LauncherModel

    init(index: AppIndex, clipboard: ClipboardStore, notes: NotesStore, config: Preferences, usage: UsageStore = UsageStore(), onNote: @escaping (LauncherAction) -> Void) {
        LauncherPanel.scale = min(1.4, max(0.8, config.appearance.scale))
        LauncherPanel.opacity = min(1.0, max(0.5, config.appearance.opacity))
        model = LauncherModel(index: index, clipboard: clipboard, notes: notes, config: config, usage: usage, onNote: onNote)
        super.init(contentRect: NSRect(origin: .zero, size: LauncherPanel.size),
                   styleMask: [.nonactivatingPanel, .borderless, .fullSizeContentView],
                   backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        isMovableByWindowBackground = true
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        isReleasedWhenClosed = false
        hidesOnDeactivate = false
        model.dismiss = { [weak self] in self?.orderOut(nil) }
        contentView = NSHostingView(rootView: LauncherView(model: model, agents: model.agents))
    }

    override var canBecomeKey: Bool { true }

    /// Clicking anywhere else, or switching apps, dismisses the panel instead of leaving it floating.
    override func resignKey() {
        super.resignKey()
        if !PermissionGate.isPrompting { orderOut(nil) }
    }

    func toggle() {
        if let modal = NSApp.modalWindow {
            if isVisible { orderOut(nil) }
            modal.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        if isVisible { orderOut(nil); return }
        model.isPresented = true
        model.reset()
        model.resumeAgentsIfNeeded()
        center(onScreenWithMouse: true)
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

    override func orderOut(_ sender: Any?) {
        model.isPresented = false
        model.agents.disconnect()
        super.orderOut(sender)
    }

    private func center(onScreenWithMouse: Bool) {
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { $0.frame.contains(mouse) } ?? NSScreen.main
        guard let frame = screen?.visibleFrame else { return }
        let origin = NSPoint(x: frame.midX - LauncherPanel.size.width / 2,
                             y: frame.midY - LauncherPanel.size.height / 2 + frame.height * 0.10)
        setFrameOrigin(origin)
    }

    /// Development aid for screenshots: `Volant --show --query saf`.
    func setQuery(_ text: String) { model.query = text }

    func apply(config: Preferences) { model.config = config }

    override func cancelOperation(_ sender: Any?) { orderOut(nil) }
}
