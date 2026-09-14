import AppKit
import SwiftUI

/// The wing is a native window drag target; text fields keep their normal selection behavior.
struct LauncherDragHandle: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView { WindowDragView() }
    func updateNSView(_ nsView: NSView, context: Context) {}
}

private final class WindowDragView: NSView {
    private var dragStart: NSPoint?
    private var windowStart: NSPoint?
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        toolTip = "Drag to move Volant"
        setAccessibilityElement(true)
        setAccessibilityRole(.group)
        setAccessibilityLabel("Move Volant window")
        setAccessibilityHelp("Drag the wing to move the window. Its position is remembered.")
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
        window.setFrameOrigin(NSPoint(x: windowStart.x + point.x - dragStart.x,
                                      y: windowStart.y + point.y - dragStart.y))
    }
    override func mouseUp(with event: NSEvent) {
        dragStart = nil
        windowStart = nil
    }
}
