import AppKit

let app = NSApplication.shared
let dark = CommandLine.arguments.contains("dark")
let empty = CommandLine.arguments.contains("empty")
let compact = CommandLine.arguments.contains("compact")
app.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
let directory = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("volant-import-render-\(UUID())")
try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
defer { try? FileManager.default.removeItem(at: directory) }
let config = directory.appendingPathComponent("config.json")
try JSONEncoder().encode(Preferences()).write(to: config)
let payload: [String: Any] = ["snippets": ["snippets": [["title": "Daily update", "text": "Today {date}: {clipboard}", "keyword": ";daily"]]], "quicklinks": ["quicklinks": [["name": "Project search", "link": "https://example.com/?q={Query}"]]], "notes": ["notes": [["title": "Next steps", "markdown": "Review the search tests."]]]]
let controller = RaycastImportWindowController(onChange: {})
let plan = try RaycastImportPlan.make(payload: JSONSerialization.data(withJSONObject: payload), configURL: config, notesURL: directory.appendingPathComponent("Notes"))
if !empty { controller.showPreview(plan) }
let window = controller.window!
window.appearance = app.appearance
if compact { window.setContentSize(NSSize(width: 560, height: 630)) }
window.makeKeyAndOrderFront(nil)
RunLoop.main.run(until: Date().addingTimeInterval(0.4))
let view = window.contentView!
view.layoutSubtreeIfNeeded()
let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds)!
view.cacheDisplay(in: view.bounds, to: rep)
let name = "/tmp/volant-import-" + (dark ? "dark" : "light") + (empty ? "-empty" : "") + (compact ? "-compact" : "") + ".jpg"
try rep.representation(using: .jpeg, properties: [.compressionFactor: 0.8])!.write(to: URL(fileURLWithPath: name))
func descendants(_ view: NSView) -> [NSView] { view.subviews.flatMap { [$0] + descendants($0) } }
let children = descendants(view)
precondition(children.contains { $0 is NSSecureTextField })
let importButton = children.compactMap { $0 as? NSButton }.first { $0.title == "Import Selected" }!
precondition(importButton.isEnabled == !empty)
if !empty {
    importButton.performClick(nil)
    precondition(!importButton.isEnabled)
    let stored = try JSONDecoder().decode(Preferences.self, from: Data(contentsOf: config))
    precondition(stored.snippets.count == 1)
    let files = try FileManager.default.contentsOfDirectory(atPath: directory.appendingPathComponent("Notes").path)
    precondition(files.count == 1)
}
print("Rendered \(name); secure field, empty/preview state, and isolated import action passed")
window.orderOut(nil)
