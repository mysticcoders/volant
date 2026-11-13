import AppKit
import Combine
import SwiftUI
import VolantCore

/// The focus bar's menu-bar form: the time left as text in the menu bar, with the session's
/// controls in a popover. It exists only while a session runs with the menu bar placement.
final class FocusStatusItem {
    private let controller: FocusController
    private let actions: FocusBarActions
    private var item: NSStatusItem?
    private var popover: NSPopover?
    private var subscription: AnyCancellable?

    init(controller: FocusController, actions: FocusBarActions) {
        self.controller = controller
        self.actions = actions
        subscription = controller.objectWillChange.sink { [weak self] in
            DispatchQueue.main.async { self?.refresh() }
        }
    }

    /// Adds, updates or removes the menu bar item to match the session.
    func refresh() {
        guard controller.isRunning, controller.placement == .menuBar else {
            popover?.close()
            if let item { NSStatusBar.system.removeStatusItem(item) }
            item = nil
            return
        }
        let item = self.item ?? makeItem()
        let paused = controller.session?.isPaused == true
        item.button?.image = NSImage(systemSymbolName: paused ? "pause.circle" : "target", accessibilityDescription: nil)
        item.button?.imagePosition = .imageLeading
        item.button?.attributedTitle = NSAttributedString(string: " " + controller.timeText(),
                                                          attributes: [.font: NSFont.monospacedDigitSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)])
        item.button?.setAccessibilityLabel(String(localized: "Focus session, \(controller.timeText(), format: .verbatim)", comment: "Accessibility label for the Focus menu bar item; the value is the time"))
    }

    private func makeItem() -> NSStatusItem {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.target = self
        item.button?.action = #selector(toggle)
        self.item = item
        return item
    }

    @objc private func toggle() {
        if let popover, popover.isShown { popover.close(); return }
        guard let button = item?.button else { return }
        let popover = self.popover ?? NSPopover()
        popover.behavior = .transient
        popover.contentViewController = NSHostingController(rootView: ThemedRoot {
            FocusBarView(controller: controller, actions: actions).padding(4)
        })
        self.popover = popover
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
    }
}
