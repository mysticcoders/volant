import AppKit
import SwiftUI

/// A floating, non-activating, borderless panel that hosts the SwiftUI launcher and toggles on the summon hotkey.
final class LauncherPanel: NSPanel {
    static let size = NSSize(width: 750, height: 480)
    private let model: LauncherModel

    init(index: AppIndex, clipboard: ClipboardStore, notes: NotesStore, onNote: @escaping (NoteAction) -> Void) {
        model = LauncherModel(index: index, clipboard: clipboard, notes: notes, onNote: onNote)
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
        contentView = NSHostingView(rootView: LauncherView(model: model))
    }

    override var canBecomeKey: Bool { true }

    /// Clicking anywhere else, or switching apps, dismisses the panel instead of leaving it floating.
    override func resignKey() {
        super.resignKey()
        if !PermissionGate.isPrompting { orderOut(nil) }
    }

    func toggle() {
        if isVisible { orderOut(nil); return }
        model.reset()
        center(onScreenWithMouse: true)
        makeKeyAndOrderFront(nil)
    }

    private func center(onScreenWithMouse: Bool) {
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { $0.frame.contains(mouse) } ?? NSScreen.main
        guard let frame = screen?.visibleFrame else { return }
        let origin = NSPoint(x: frame.midX - LauncherPanel.size.width / 2,
                             y: frame.midY - LauncherPanel.size.height / 2 + frame.height * 0.10)
        setFrameOrigin(origin)
    }

    /// Development aid for screenshots: `Vey --show --query saf`.
    func setQuery(_ text: String) { model.query = text }

    override func cancelOperation(_ sender: Any?) { orderOut(nil) }
}
