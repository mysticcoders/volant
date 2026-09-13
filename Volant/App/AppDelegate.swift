import AppKit
import ServiceManagement

/// Owns the long-lived services: menu bar item, hotkeys, app index, clipboard monitor, and the panel.
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?
    private var config = Preferences.load()
    private let index = AppIndex()
    private lazy var clipboardStore = ClipboardStore(retention: config.clipboardRetention)
    private lazy var clipboardMonitor = ClipboardMonitor(store: clipboardStore)
    private let notesStore = NotesStore()
    private lazy var notesPanel = NotesPanel(store: notesStore)
    private lazy var panel = LauncherPanel(index: index, clipboard: clipboardStore, notes: notesStore, config: config) { [weak self] action in
        switch action {
        case .open(let id): self?.notesPanel.open(noteID: id)
        case .create(let text): self?.notesPanel.openNew(text: text)
        }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        installStatusItem()
        index.start()
        clipboardMonitor.start()
        registerHotKeys()
        if let i = CommandLine.arguments.firstIndex(of: "--run-extension"), CommandLine.arguments.indices.contains(i + 1) {
            let manager = ExtensionManager()
            manager.onLog = { print("log: \($0)") }
            manager.reload()
            let input = CommandLine.arguments.indices.contains(i + 2) ? CommandLine.arguments[i + 2] : ""
            guard let ext = manager.search(CommandLine.arguments[i + 1]).first else { print("no such extension"); exit(2) }
            manager.run(ext, input: input) { result in
                switch result {
                case .success(let out): print("result: \(out)"); exit(0)
                case .failure(let err): print("error: \(err.localizedDescription)"); exit(1)
                }
            }
            return
        }
        if CommandLine.arguments.contains("--register-login") {
            try? SMAppService.mainApp.register()
            print("login item: \(SMAppService.mainApp.status == .enabled ? "enabled" : "not enabled")")
        }
        if config.showOnLaunch && !CommandLine.arguments.contains("--show") && !CommandLine.arguments.contains("--notes") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in self?.panel.toggle() }
        }
        if CommandLine.arguments.contains("--notes") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self] in self?.notesPanel.toggle() }
        }
        if CommandLine.arguments.contains("--show") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self] in
                guard let self else { return }
                self.panel.toggle()
                if let i = CommandLine.arguments.firstIndex(of: "--query"), CommandLine.arguments.indices.contains(i + 1) {
                    self.panel.setQuery(CommandLine.arguments[i + 1])
                }
            }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        clipboardMonitor.stop()
        notesStore.flush()
        HotKeyCenter.shared.unregisterAll()
    }

    private func installStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let wing = NSImage(named: "VolantWing") {
            wing.size = NSSize(width: 16, height: 16)
            wing.isTemplate = true
            item.button?.image = wing
        } else {
            item.button?.image = NSImage(systemSymbolName: "arrow.up.forward.circle", accessibilityDescription: "Volant")
        }
        item.button?.setAccessibilityLabel("Volant")
        let menu = NSMenu()
        menu.addItem(withTitle: "Show Volant", action: #selector(togglePanel), keyEquivalent: "")
        menu.addItem(withTitle: "Notes", action: #selector(toggleNotes), keyEquivalent: "")
        menu.addItem(withTitle: "Reveal Config Folder", action: #selector(revealConfig), keyEquivalent: "")
        menu.addItem(withTitle: "Reload Config", action: #selector(reloadConfig), keyEquivalent: "")
        menu.addItem(withTitle: "Export Backup…", action: #selector(exportBackup), keyEquivalent: "")
        menu.addItem(withTitle: "Import Backup…", action: #selector(importBackup), keyEquivalent: "")
        let login = NSMenuItem(title: "Launch at Login", action: #selector(toggleLoginItem), keyEquivalent: "")
        login.state = SMAppService.mainApp.status == .enabled ? .on : .off
        menu.addItem(login)
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit Volant", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.items.forEach { $0.target = $0.action == #selector(NSApplication.terminate(_:)) ? NSApp : self }
        item.menu = menu
        statusItem = item
    }

    private func registerHotKeys() {
        HotKeyCenter.shared.unregisterAll()
        if let combo = KeyCombo(parsing: config.summonHotKey) {
            HotKeyCenter.shared.register(combo) { [weak self] in self?.togglePanel() }
        }
        if let combo = KeyCombo(parsing: config.notesHotKey) {
            HotKeyCenter.shared.register(combo) { [weak self] in self?.toggleNotes() }
        }
        AppHotKeys.register(config.appHotKeys)
    }

    @objc private func toggleNotes() { notesPanel.toggle() }

    @objc private func togglePanel() { panel.toggle() }

    @objc private func toggleLoginItem(_ sender: NSMenuItem) {
        if SMAppService.mainApp.status == .enabled {
            try? SMAppService.mainApp.unregister()
        } else {
            try? SMAppService.mainApp.register()
        }
        sender.state = SMAppService.mainApp.status == .enabled ? .on : .off
    }

    @objc private func revealConfig() {
        NSWorkspace.shared.activateFileViewerSelecting([Preferences.configURL])
    }

    @objc private func exportBackup() { Backup.export() }
    @objc private func importBackup() { if Backup.importBackup() { reloadConfig() } }

    @objc private func reloadConfig() {
        config = Preferences.load()
        registerHotKeys()
        panel.apply(config: config)
        clipboardStore.retention = config.clipboardRetention
        if let error = Preferences.loadError {
            let alert = NSAlert()
            alert.messageText = "Config not applied"
            alert.informativeText = error
            alert.runModal()
        }
    }
}
