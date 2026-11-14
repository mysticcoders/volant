import AppKit
import SwiftUI
import VolantCore

/// The Welcome window. Closing it at any page, with Done, Skip Setup, the close button or Escape,
/// records it as completed on this Mac.
final class WelcomeWindowController: NSWindowController, NSWindowDelegate {
    let model: WelcomeModel
    private let onFinish: () -> Void
    private var finished = false

    init(model: WelcomeModel, onFinish: @escaping () -> Void) {
        self.model = model
        self.onFinish = onFinish
        let window = WelcomePanel(contentRect: NSRect(x: 0, y: 0, width: 680, height: 620),
                                  styleMask: [.titled, .closable, .fullSizeContentView], backing: .buffered, defer: false)
        window.title = String(localized: "Welcome to Volant", comment: "Welcome window title")
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.collectionBehavior = [.fullScreenNone]
        window.hidesOnDeactivate = false
        window.isReleasedWhenClosed = false
        super.init(window: window)
        window.delegate = self
        let hosting = NSHostingView(rootView: ThemedRoot(paletteText: false) {
            WelcomeView(model: model) { [weak self] in self?.close() }
                .frame(width: 680, height: 620)
                .ignoresSafeArea(.container, edges: .top)
        })
        hosting.sizingOptions = []
        window.contentView = hosting
        window.center()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    /// Shows the window from its first page and brings Volant forward.
    func present() {
        finished = false
        model.step = .shortcut
        model.start()
        showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func windowWillClose(_ notification: Notification) {
        guard !finished else { return }
        finished = true
        model.stop()
        onFinish()
    }
}

/// Lets Escape close the window, which counts as finishing it, as Settings closes on Escape.
final class WelcomePanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
    override func cancelOperation(_ sender: Any?) {
        guard attachedSheet == nil else { return }
        close()
    }
}
