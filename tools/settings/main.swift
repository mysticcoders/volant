import AppKit
import CryptoKit
import SwiftUI

let app = NSApplication.shared
app.setActivationPolicy(.regular)
app.appearance = NSAppearance(named: CommandLine.arguments.contains("dark") ? .darkAqua : .aqua)
let root = FileManager.default.temporaryDirectory.appendingPathComponent("volant-settings-" + UUID().uuidString)
try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
let configURL = root.appendingPathComponent("config.json")
try Data(#"{"aliases":{"safari":"/Applications/Safari.app"},"appHotKeys":[]}"#.utf8).write(to: configURL)
let apps = [AppEntry(id: "/System/Applications/Calculator.app", name: "Calculator", url: URL(fileURLWithPath: "/System/Applications/Calculator.app"), lastUsed: nil), AppEntry(id: "/Applications/Safari.app", name: "Safari", url: URL(fileURLWithPath: "/Applications/Safari.app"), lastUsed: nil)]
var controller: SettingsWindowController!
controller = SettingsWindowController(configURL: configURL) {
    HotKeyCenter.shared.unregisterAll()
    AppHotKeys.register((try? JSONDecoder().decode(Preferences.self, from: Data(contentsOf: configURL)))?.appHotKeys ?? [])
    controller.refresh(try! JSONDecoder().decode(Preferences.self, from: Data(contentsOf: configURL)), apps: apps)
}
controller.refresh(try JSONDecoder().decode(Preferences.self, from: Data(contentsOf: configURL)), apps: apps)
let clipboard = ClipboardStore(retention: 10, storageURL: root.appendingPathComponent("clipboard.sqlite"), encryptionKey: SymmetricKey(size: .bits256))
let notes = NotesStore(directory: root.appendingPathComponent("Notes"))
let usage = UsageStore(url: root.appendingPathComponent("usage.sqlite"))
let panel = LauncherPanel(index: AppIndex(entries: apps), clipboard: clipboard, notes: notes, config: Preferences(), usage: usage, positionStore: UserDefaults(suiteName: "volant.settings.preview")!) { action in
    if case .editApp(let entry) = action { controller.edit(entry) }
}
panel.model.searchesSecondarySources = false
final class PreviewActions: NSObject {
    let show: () -> Void
    init(show: @escaping () -> Void) { self.show = show }
    @objc func showLauncher() { show() }
    @objc func settings() { controller.showWindow(nil) }
    @objc func updates() {}
}
let actions = PreviewActions { panel.toggle(); panel.setQuery("Calculator") }
let menu = NSMenu()
let item = NSMenuItem()
let submenu = NSMenu()
let launchItem = submenu.addItem(withTitle: "Show Launcher", action: #selector(PreviewActions.showLauncher), keyEquivalent: "l")
launchItem.target = actions
submenu.addItem(withTitle: "Quit Preview", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
item.submenu = submenu; menu.addItem(item); app.mainMenu = menu
let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
statusItem.isVisible = CommandLine.arguments.contains("--menu")
statusItem.button?.image = NSImage(named: "VolantWing")
statusItem.button?.image?.size = NSSize(width: 16, height: 16)
statusItem.button?.image?.isTemplate = true
statusItem.button?.setAccessibilityLabel("Volant Settings Preview")
statusItem.menu = StatusMenu.make(target: actions, show: #selector(PreviewActions.showLauncher), settings: #selector(PreviewActions.settings), update: #selector(PreviewActions.updates))
controller.window?.setFrame(NSWindow.frameRect(forContentRect: NSRect(x: 100, y: 100, width: 680, height: 500), styleMask: controller.window!.styleMask), display: true)
var destinationWindow: NSWindow?
if CommandLine.arguments.contains("--snap") {
    _ = NotificationCenter.default.addObserver(forName: NSWindow.didMoveNotification, object: panel, queue: .main) { _ in
        print("Snap fixture position: \(panel.frame.origin)"); fflush(stdout)
    }
    // Retain this isolated fixture when computer-use inspection shifts app focus.
    // No connectivity operation is started; ordinary blur is tested in check-launcher.
    panel.model.connectivityBusy = true
    DispatchQueue.main.async {
        app.activate(ignoringOtherApps: true)
        panel.toggle()
        panel.setQuery("Calculator")
    }
} else if CommandLine.arguments.contains("--destinations") {
    panel.model.query = "settings login"
    let host = NSHostingView(rootView: LauncherView(model: panel.model, agents: panel.model.agents).background(Color(nsColor: .windowBackgroundColor)))
    destinationWindow = NSWindow(contentRect: NSRect(origin: .zero, size: LauncherPanel.size), styleMask: [.titled, .closable], backing: .buffered, defer: false)
    destinationWindow?.title = "Settings Destination Preview"
    destinationWindow?.contentView = host
    destinationWindow?.center()
    destinationWindow?.makeKeyAndOrderFront(nil)
    app.activate(ignoringOtherApps: true)
} else if !CommandLine.arguments.contains("--render") {
    controller.showWindow(nil)
    app.activate(ignoringOtherApps: true)
}
print("Settings preview ready; isolated config: \(configURL.path)")
fflush(stdout)
if CommandLine.arguments.contains("--menu") {
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
        statusItem.menu?.popUp(positioning: nil, at: NSPoint(x: 40, y: 100), in: controller.window?.contentView)
    }
}
if CommandLine.arguments.contains("--render") {
    DispatchQueue.main.async {
        let output = URL(fileURLWithPath: "/tmp/volant-settings-renders")
        try! FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        for theme in ["light", "dark"] {
            app.appearance = NSAppearance(named: theme == "dark" ? .darkAqua : .aqua)
            for section in ["General", "App Shortcuts", "Data & Configuration"] {
                controller.state.section = section
                controller.window!.setFrame(NSWindow.frameRect(forContentRect: NSRect(x: 100, y: 100, width: 680, height: 500), styleMask: controller.window!.styleMask), display: true)
                RunLoop.main.run(until: Date().addingTimeInterval(0.15))
                let view = controller.window!.contentView!
                view.layoutSubtreeIfNeeded()
                precondition(abs(view.bounds.width - 680) < 1 && abs(view.bounds.height - 500) < 1, "Settings fixture changed size")
                func recorders(_ view: NSView) -> [RecorderButton] {
                    (view as? RecorderButton).map { [$0] } ?? view.subviews.flatMap(recorders)
                }
                if section == "General" {
                    let event = NSEvent.mouseEvent(with: .mouseMoved, location: .zero, modifierFlags: [], timestamp: 0,
                                                   windowNumber: controller.window!.windowNumber, context: nil, eventNumber: 0, clickCount: 0, pressure: 0)!
                    for recorder in recorders(view) {
                        recorder.mouseEntered(with: event)
                        precondition(recorder.subviews.contains { !$0.isHidden && ($0 as? NSButton)?.toolTip == "Remove shortcut" })
                    }
                }
                let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds)!
                view.cacheDisplay(in: view.bounds, to: rep)
                try! rep.representation(using: .png, properties: [:])!.write(to: output.appendingPathComponent(theme + "-" + section + ".png"))
                print("Rendered \(theme) \(section): \(view.bounds.size)")
            }
        }
        app.terminate(nil)
    }
}
app.run()
