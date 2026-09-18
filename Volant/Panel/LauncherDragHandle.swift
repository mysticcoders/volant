import AppKit
import SwiftUI

/// Native targets on the top edge and wing leave text selection and controls intact.
struct LauncherDragHandle: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView { WindowDragView() }
    func updateNSView(_ nsView: NSView, context: Context) {}
}

final class WindowDragView: NSView {
    private var dragStart: NSPoint?
    private var windowStart: NSPoint?
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        toolTip = "Drag to align Volant. Hold Option to move freely."
        setAccessibilityElement(true)
        setAccessibilityRole(.group)
        setAccessibilityLabel("Move Volant window")
        setAccessibilityHelp("Drag to align the window to the screen's three-by-three placement grid. Hold Option to move freely. Its position is remembered.")
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override var mouseDownCanMoveWindow: Bool { false }
    override func resetCursorRects() { addCursorRect(bounds, cursor: .openHand) }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func mouseDown(with event: NSEvent) {
        guard let window else { return }
        dragStart = window.convertPoint(toScreen: event.locationInWindow)
        windowStart = window.frame.origin
    }
    override func mouseDragged(with event: NSEvent) {
        guard let window, let dragStart, let windowStart else { return }
        let point = window.convertPoint(toScreen: event.locationInWindow)
        let origin = NSPoint(x: windowStart.x + point.x - dragStart.x, y: windowStart.y + point.y - dragStart.y)
        if let launcher = window as? LauncherPanel {
            launcher.drag(to: origin, pointer: point, freely: event.modifierFlags.contains(.option))
        } else { window.setFrameOrigin(origin) }
    }
    override func mouseUp(with event: NSEvent) {
        (window as? LauncherPanel)?.endDragging()
        dragStart = nil
        windowStart = nil
    }
}
