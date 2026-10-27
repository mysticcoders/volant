import AppKit
import SwiftUI
import VolantCore

/// The Rex Overview's window. Its keys reach the overview before SwiftUI's scroll view, which would
/// otherwise take the arrows for scrolling; any key the handler declines is delivered as usual.
final class RexOverviewWindow: NSWindow {
    var keyHandler: ((NSEvent) -> Bool)?

    override func sendEvent(_ event: NSEvent) {
        if event.type == .keyDown, keyHandler?(event) == true { return }
        super.sendEvent(event)
    }
}

/// The Rex Overview: an ordinary resizable window, opened from the `rex` view, that reads Rex only
/// while it is open and pane previews are on. Closing it disconnects and forgets everything read.
final class RexOverviewWindowController: NSWindowController, NSWindowDelegate {
    let model: RexOverviewModel

    init(model: RexOverviewModel = RexOverviewModel()) {
        self.model = model
        let window = RexOverviewWindow(contentRect: NSRect(x: 0, y: 0, width: 980, height: 640),
                              styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        window.title = String(localized: "Rex Overview", comment: "Window title")
        window.minSize = NSSize(width: 640, height: 420)
        window.isReleasedWhenClosed = false
        window.hidesOnDeactivate = false
        window.setFrameAutosaveName("VolantRexOverview")
        super.init(window: window)
        window.delegate = self
        window.contentView = NSHostingView(rootView: ThemedRoot(paletteText: false) {
            RexOverviewView(model: model, close: { [weak window] in window?.performClose(nil) })
        })
        if !window.setFrameUsingName("VolantRexOverview") { window.center() }
        window.keyHandler = { [weak self, weak window] event in
            guard let self, let window else { return false }
            return Self.handle(event, model: self.model, close: { window.performClose(nil) })
        }
    }

    /// Plain arrows, Tab, Return, Space (minimize or expand the session) and Escape drive the overview;
    /// anything with Command, Option or
    /// Control passes through, so menus and Command-W still work. Moves and Return apply only while
    /// the grid shows, so Return on the approval card still presses its default button.
    static func handle(_ event: NSEvent, model: RexOverviewModel, close: () -> Void) -> Bool {
        let modifiers = event.modifierFlags.intersection([.command, .option, .control, .shift])
        guard modifiers.isDisjoint(with: [.command, .option, .control]) else { return false }
        let shift = modifiers.contains(.shift)
        if event.keyCode == 53 && !shift { close(); return true }
        guard model.keyboardActive else { return false }
        let move: RexOverview.Move?
        switch event.keyCode {
        case 123 where !shift: move = .previousTab
        case 124 where !shift: move = .nextTab
        case 126 where !shift: move = .previousPane
        case 125 where !shift: move = .nextPane
        case 48: move = shift ? .previousWaiting : .nextWaiting
        case 36 where !shift, 76 where !shift: model.focusSelection(); return true
        case 49 where !shift: model.toggleSelectedSession(); return true
        default: move = nil
        }
        guard let move else { return false }
        model.move(move)
        return true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    func show() {
        model.windowOpened()
        showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func windowWillClose(_ notification: Notification) { model.windowClosed() }
}
