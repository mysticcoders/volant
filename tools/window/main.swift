import AppKit
import CryptoKit

let app = NSApplication.shared
app.setActivationPolicy(.regular)
let dark = CommandLine.arguments.contains("dark")
app.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
let clipboard = ClipboardStore(retention: 10, storageURL: root.appendingPathComponent("clipboard.sqlite"), encryptionKey: SymmetricKey(size: .bits256))
let notes = NotesStore(directory: root.appendingPathComponent("Notes"))
let usage = UsageStore(url: root.appendingPathComponent("usage.sqlite"))
let defaults = UserDefaults(suiteName: "volant.window.preview")!
let panel = LauncherPanel(index: AppIndex(), clipboard: clipboard, notes: notes, config: Preferences(), usage: usage, positionStore: defaults, onNote: { _ in })
panel.model.searchesSecondarySources = false
panel.model.presentAIChat()
panel.model.acp.project = "/fictional/orbit-web"
panel.model.acp.state.phase = "working"
panel.model.acp.state.status = "Working · fictional preview"
panel.model.acp.state.messages = [ACPMessage(role: "You", text: "Review the navigation in this fictional project."), ACPMessage(role: "Agent", text: "I’m checking the navigation. You can switch to another app while this conversation stays visible.")]
let menu = NSMenu()
let appItem = NSMenuItem()
let appMenu = NSMenu()
appMenu.addItem(withTitle: "Quit Preview", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
appItem.submenu = appMenu; menu.addItem(appItem); app.mainMenu = menu
panel.toggle()
app.activate(ignoringOtherApps: true)
print("Window preview ready at \(panel.frame.origin)")
fflush(stdout)
let moveObserver = NotificationCenter.default.addObserver(forName: NSWindow.didMoveNotification, object: panel, queue: .main) { _ in
    print("Preview moved to \(panel.frame.origin); saved: \(defaults.dictionary(forKey: "launcherPosition") ?? [:])")
    fflush(stdout)
}
app.run()
