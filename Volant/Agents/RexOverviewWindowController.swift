import AppKit
import SwiftUI

/// The Rex Overview: an ordinary resizable window, opened from the `rex` view, that reads Rex only
/// while it is open and pane previews are on. Closing it disconnects and forgets everything read.
final class RexOverviewWindowController: NSWindowController, NSWindowDelegate {
    let model: RexOverviewModel

    init(model: RexOverviewModel = RexOverviewModel()) {
        self.model = model
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 980, height: 640),
                              styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        window.title = "Rex Overview"
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
