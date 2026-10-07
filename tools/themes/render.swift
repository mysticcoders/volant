import AppKit
import CryptoKit
import SwiftUI
import VolantCore

/// Renders the launcher, a calculator card, the actions popover and the notes window in every color
/// theme with fictional data, for visual inspection. Palette themes render in their own appearance;
/// System and Volant render light and dark. Images go to /tmp/volant-theme-<id>-<mode>-<surface>.png.
setbuf(stdout, nil)
let app = NSApplication.shared
let root = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : NSTemporaryDirectory())
    .appendingPathComponent("volant-themes-" + UUID().uuidString)
try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
let clipboard = ClipboardStore(retention: 10, storageURL: root.appendingPathComponent("clipboard.sqlite"), encryptionKey: SymmetricKey(size: .bits256))
let usage = UsageStore(url: root.appendingPathComponent("usage.sqlite"))
let notesDirectory = root.appendingPathComponent("Notes")
try FileManager.default.createDirectory(at: notesDirectory, withIntermediateDirectories: true)
try "# Trip checklist\n\n## Before Friday\n\n- Pack the **blue** bag\n- Check the [route](https://example.com/route)\n- Bring `charger` and cards\n\n> Leave by 7:30.\n\n```swift\nlet bags = 2\nlet note = \"Window seat\"\n```\n"
    .write(to: notesDirectory.appendingPathComponent("Trip checklist.md"), atomically: true, encoding: .utf8)
let notes = NotesStore(directory: notesDirectory)
let model = LauncherModel(index: AppIndex(), clipboard: clipboard, notes: notes, config: Preferences(), usage: usage) { _ in }
model.searchesSecondarySources = false
var config = Preferences()
config.snippets = [Snippet(name: "Standup notes", keyword: "", body: "Fictional"), Snippet(name: "Status update", keyword: "", body: "Fictional"),
                   Snippet(name: "Support reply", keyword: "", body: "Fictional")]
model.config = config

let host = NSHostingView(rootView: ThemedRoot { ThemedLauncher(model: model) })
let window = NSWindow(contentRect: NSRect(origin: .zero, size: LauncherPanel.size), styleMask: [.borderless], backing: .buffered, defer: false)
window.contentView = host
window.makeKeyAndOrderFront(nil)
let notesModel = NotesModel(store: notes)
let notesHost = NSHostingView(rootView: ThemedRoot { NotesView(model: notesModel) })
let notesWindow = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 460, height: 480), styleMask: [.titled, .fullSizeContentView], backing: .buffered, defer: false)
notesWindow.contentView = notesHost
notesWindow.orderFront(nil)

/// Writes a view's current drawing to a PNG.
func capture(_ view: NSView, _ name: String) throws {
    view.layoutSubtreeIfNeeded()
    let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds)!
    view.cacheDisplay(in: view.bounds, to: bitmap)
    try bitmap.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: "/tmp/volant-theme-\(name).png"))
}

for theme in ColorTheme.catalog {
    for mode in theme.mode.map({ [$0] }) ?? [ColorTheme.Mode.light, .dark] {
        let setting: Appearance.Theme = mode == .dark ? .dark : .light
        MainActor.assumeIsolated { ThemeStore.shared.apply(Appearance(theme: setting, colorTheme: theme.id)) }
        window.appearance = NSApp.appearance
        notesWindow.appearance = NSApp.appearance
        let name = "\(theme.id)-\(mode.rawValue)"
        model.actionTarget = nil
        model.query = "snip s"
        model.selection = 1
        RunLoop.main.run(until: Date().addingTimeInterval(0.3))
        try capture(host, name + "-rows")
        model.actionTarget = model.selectedRow
        RunLoop.main.run(until: Date().addingTimeInterval(0.3))
        try capture(host, name + "-actions")
        model.actionTarget = nil
        model.query = "#3a7bd5 in oklch"
        RunLoop.main.run(until: Date().addingTimeInterval(0.3))
        try capture(host, name + "-card")
        notesModel.selectIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.3))
        try capture(notesHost, name + "-notes")
        print("Rendered \(name)")
    }
}
let imported = try RaycastTheme.parse("raycast://theme?name=Harbor%20Night&appearance=dark&colors=%23101418,%230C1014,%23E8ECF0,%232A3440,%237A8490,%23F06060,%23F09050,%23E8C860,%2370C080,%236CA8F0,%23A890F0,%23E080C8")
MainActor.assumeIsolated {
    ThemeStore.shared.apply(Appearance(colorTheme: imported.customTheme.id, customThemes: [imported.customTheme]))
}
window.appearance = NSApp.appearance
model.query = "snip s"
model.selection = 1
RunLoop.main.run(until: Date().addingTimeInterval(0.3))
try capture(host, "imported-dark-rows")
model.query = "#3a7bd5 in oklch"
RunLoop.main.run(until: Date().addingTimeInterval(0.3))
try capture(host, "imported-dark-card")
print("PASS: rendered \(ColorTheme.catalog.count) color themes and an imported Raycast theme")
exit(0)
