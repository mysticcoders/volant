import AppKit
import SwiftUI
import CryptoKit
import VolantCore

let app = NSApplication.shared
let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
let clipboard = ClipboardStore(retention: 10, storageURL: root.appendingPathComponent("clipboard.sqlite"), encryptionKey: SymmetricKey(size: .bits256))
let notes = NotesStore(directory: root.appendingPathComponent("Notes"))
let usage = UsageStore(url: root.appendingPathComponent("usage.sqlite"))
let model = LauncherModel(index: AppIndex(), clipboard: clipboard, notes: notes, config: Preferences(), usage: usage, onNote: { _ in })
model.searchesSecondarySources = false
model.query = "sa"
model.promotedHarness = "all"
model.agents.connected = true
model.agents.sessions = [
    AgentSession(agent: "claude", agentStatus: "blocked", paneID: "2", terminalID: "fixture-2", cwd: "/fictional/orbit-api", terminalTitle: nil, agentSession: nil),
    AgentSession(agent: "codex", agentStatus: "working", paneID: "1", terminalID: "fixture-1", cwd: "/fictional/orbit-web", terminalTitle: nil, agentSession: nil),
    AgentSession(agent: "opencode", agentStatus: "working", paneID: "3", terminalID: "fixture-3", cwd: "/fictional/orbit-docs", terminalTitle: nil, agentSession: nil)
]
model.sections = [ResultSection(title: "Applications", rows: [
    .app(AppEntry(id: "safari", name: "Safari", url: URL(fileURLWithPath: "/System/Volumes/Preboot/Cryptexes/App/System/Applications/Safari.app"), lastUsed: nil)),
    .app(AppEntry(id: "settings", name: "System Settings", url: URL(fileURLWithPath: "/System/Applications/System Settings.app"), lastUsed: nil))
])]
let defaults = UserDefaults(suiteName: "volant.marketing.fixture")!
defaults.set(true, forKey: "showHerdrDetails")
for dark in [false, true] {
    app.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
    let host = NSHostingView(rootView: LauncherView(model: model, agents: model.agents)
        .defaultAppStorage(defaults)
        .accentColor(Color("AccentColor"))
        .background(Color(nsColor: .windowBackgroundColor)))
    let window = NSWindow(contentRect: NSRect(origin: .zero, size: LauncherPanel.size), styleMask: [.borderless], backing: .buffered, defer: false)
    window.appearance = app.appearance
    window.contentView = host
    window.makeKeyAndOrderFront(nil)
    RunLoop.main.run(until: Date().addingTimeInterval(0.6))
    (window.firstResponder as? NSTextView)?.setSelectedRange(NSRange(location: 2, length: 0))
    host.layoutSubtreeIfNeeded()
    let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds)!
    host.cacheDisplay(in: host.bounds, to: rep)
    try rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: CommandLine.arguments[1]).appendingPathComponent("launcher-\(dark ? "dark" : "light").png"))
    window.orderOut(nil)
}
defaults.removePersistentDomain(forName: "volant.marketing.fixture")
print("Rendered native launcher with fictional Herdr activity in light and dark appearances")
