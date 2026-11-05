import AppKit
import SwiftUI
import CryptoKit
import VolantCore

// Renders the README demo as numbered frames of the real LauncherView with fictional data:
// /tmp/volant-demo-NNN-MS.png, where MS is how long the frame shows. tools/render-demo.sh runs it in the
// render VM through tools/render-vm.py --demo and assembles the frames into an animated WebP.
let app = NSApplication.shared
app.appearance = NSAppearance(named: .darkAqua)
let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
let clipboard = ClipboardStore(retention: 10, storageURL: root.appendingPathComponent("clipboard.sqlite"), encryptionKey: SymmetricKey(size: .bits256))
let notes = NotesStore(directory: root.appendingPathComponent("Notes"))
let usage = UsageStore(url: root.appendingPathComponent("usage.sqlite"))
let model = LauncherModel(index: AppIndex(), clipboard: clipboard, notes: notes, config: Preferences(), usage: usage, onNote: { _ in })
model.searchesSecondarySources = false
model.promotedHarness = "all"
model.agents.connected = true
model.agents.sessions = [
    AgentSession(agent: "claude", agentStatus: "blocked", paneID: "2", terminalID: "fixture-2", cwd: "/fictional/orbit-api", terminalTitle: nil, agentSession: .init(value: "claude-fictional")),
    AgentSession(agent: "codex", agentStatus: "working", paneID: "1", terminalID: "fixture-1", cwd: "/fictional/orbit-web", terminalTitle: nil, agentSession: nil),
    AgentSession(agent: "opencode", agentStatus: "working", paneID: "3", terminalID: "fixture-3", cwd: "/fictional/orbit-docs", terminalTitle: nil, agentSession: nil)
]
// The waiting agent's question comes from this fictional reply instead of a running Herdr.
let question = try JSONEncoder().encode(HerdrResponseController.Snapshot(
    text: "Allow running npm test in /fictional/orbit-api?\n\n1. Yes, once\n2. Yes, for this session\n3. No", token: nil, question: nil))
model.agents.attentionReader = { _, reply in reply(question, nil) }
let safari = ResultRow.app(AppEntry(id: "safari", name: "Safari", url: URL(fileURLWithPath: "/System/Volumes/Preboot/Cryptexes/App/System/Applications/Safari.app"), lastUsed: nil))
let settings = ResultRow.app(AppEntry(id: "settings", name: "System Settings", url: URL(fileURLWithPath: "/System/Applications/System Settings.app"), lastUsed: nil))
let shortcuts = ResultRow.app(AppEntry(id: "shortcuts", name: "Shortcuts", url: URL(fileURLWithPath: "/System/Applications/Shortcuts.app"), lastUsed: nil))

let defaults = UserDefaults(suiteName: "volant.demo.fixture")!
let host = NSHostingView(rootView: LauncherView(model: model, agents: model.agents)
    .defaultAppStorage(defaults)
    .accentColor(Color("AccentColor"))
    .background(Color(nsColor: .windowBackgroundColor)))
let window = NSWindow(contentRect: NSRect(origin: .zero, size: LauncherPanel.size), styleMask: [.borderless], backing: .buffered, defer: false)
window.appearance = app.appearance
window.contentView = host
window.makeKeyAndOrderFront(nil)
RunLoop.main.run(until: Date().addingTimeInterval(0.8))
var frame = 0

/// Shows `query` with the caret at its end, optionally replacing the results the app would compute
/// with fictional rows, and writes one frame shown for `milliseconds`.
func shoot(_ query: String, rows: [ResultRow]? = nil, title: String = "Applications", milliseconds: Int) throws {
    model.query = query
    RunLoop.main.run(until: Date().addingTimeInterval(0.25))
    if let rows { model.sections = rows.isEmpty ? [] : [ResultSection(title: title, rows: rows)] }
    RunLoop.main.run(until: Date().addingTimeInterval(0.15))
    (window.firstResponder as? NSTextView)?.setSelectedRange(NSRange(location: (query as NSString).length, length: 0))
    host.layoutSubtreeIfNeeded()
    let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds)!
    host.cacheDisplay(in: host.bounds, to: rep)
    let name = String(format: "/tmp/volant-demo-%03d-%d.png", frame, milliseconds)
    try rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: name))
    frame += 1
}

/// Types `text` one character per frame, then holds the finished query.
func type(_ text: String, rows: (String) -> [ResultRow]? = { _ in nil }, hold: Int) throws {
    for count in 1...text.count {
        let prefix = String(text.prefix(count))
        try shoot(prefix, rows: rows(prefix), milliseconds: count == text.count ? hold : 110)
    }
}

try shoot("", rows: [], milliseconds: 1000)
try type("saf", rows: { $0 == "s" ? [safari, settings, shortcuts] : [safari] }, hold: 1800)
try shoot("", rows: [], milliseconds: 300)
try type("12% of 840", hold: 2200)
try shoot("", rows: [], milliseconds: 300)
try type("agents", hold: 3200)
window.orderOut(nil)
defaults.removePersistentDomain(forName: "volant.demo.fixture")
print("Rendered \(frame) demo frames with fictional data")
