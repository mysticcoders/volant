import AppKit

/// A reusable native settings surface. Controls use system colors in both appearances.
final class SettingsWindowController: NSWindowController {
    private let dock = NSButton(checkboxWithTitle: "Show Volant in the Dock", target: nil, action: nil)
    private let launch = NSButton(checkboxWithTitle: "Show launcher when Volant starts", target: nil, action: nil)
    private let harness = NSPopUpButton(frame: .zero, pullsDown: false)
    private var previousHarness: String?
    private let onChange: () -> Void

    init(onChange: @escaping () -> Void) {
        self.onChange = onChange
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 500, height: 330),
                              styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.title = "Volant Settings"
        window.isReleasedWhenClosed = false
        window.setFrameAutosaveName("VolantSettings")
        super.init(window: window)
        let title = NSTextField(labelWithString: "General")
        title.font = .systemFont(ofSize: 17, weight: .semibold)
        let hint = NSTextField(wrappingLabelWithString: "Turn off the Dock icon to use Volant from the menu bar and keyboard shortcuts.")
        hint.textColor = .secondaryLabelColor
        let config = NSButton(title: "Open Configuration File…", target: self, action: #selector(openConfig))
        config.bezelStyle = .rounded
        dock.target = self
        dock.action = #selector(changeDock)
        launch.target = self
        launch.action = #selector(changeLaunch)
        harness.addItem(withTitle: "None")
        for option in Preferences.harnessOptions { harness.addItem(withTitle: option.title) }
        harness.target = self
        harness.action = #selector(changeHarness)
        let harnessRow = NSStackView(views: [NSTextField(labelWithString: "Pinned harness"), harness])
        harnessRow.orientation = .horizontal
        harnessRow.spacing = 14
        let harnessHint = NSTextField(wrappingLabelWithString: "Show its Herdr pane status below the launcher’s search field. Connects while the launcher is open.")
        harnessHint.textColor = .secondaryLabelColor
        let stack = NSStackView(views: [title, dock, hint, launch, harnessRow, harnessHint, config])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 14
        stack.translatesAutoresizingMaskIntoConstraints = false
        window.contentView?.addSubview(stack)
        if let content = window.contentView {
            NSLayoutConstraint.activate([
                stack.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 24),
                stack.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -24),
                stack.topAnchor.constraint(equalTo: content.topAnchor, constant: 24),
                stack.bottomAnchor.constraint(lessThanOrEqualTo: content.bottomAnchor, constant: -20)
            ])
        }
        window.center()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func refresh(_ config: Preferences) {
        previousHarness = config.promotedHarness
        harness.selectItem(at: Preferences.harnessOptions.firstIndex(where: { $0.id == config.promotedHarness }).map { $0 + 1 } ?? 0)
        dock.state = config.showInDock ? .on : .off
        launch.state = config.showOnLaunch ? .on : .off
    }

    @objc private func changeHarness() {
        let index = harness.indexOfSelectedItem
        let id = index > 0 ? Preferences.harnessOptions[index - 1].id : nil
        do {
            try Preferences.updatePromotedHarness(id)
            previousHarness = id
            onChange()
        } catch {
            harness.selectItem(at: Preferences.harnessOptions.firstIndex(where: { $0.id == previousHarness }).map { $0 + 1 } ?? 0)
            let alert = NSAlert(error: error)
            alert.messageText = "Couldn’t save pinned harness"
            if let window { alert.beginSheetModal(for: window) }
        }
    }

    @objc private func changeDock() { save("showInDock", button: dock) }
    @objc private func changeLaunch() { save("showOnLaunch", button: launch) }
    @objc private func openConfig() { NSWorkspace.shared.open(Preferences.configURL) }

    private func save(_ key: String, button: NSButton) {
        do {
            try Preferences.updateBoolean(key, value: button.state == .on)
            onChange()
            window?.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
        } catch {
            button.state = button.state == .on ? .off : .on
            let alert = NSAlert(error: error)
            alert.messageText = "Couldn’t save settings"
            if let window { alert.beginSheetModal(for: window) }
        }
    }
}
