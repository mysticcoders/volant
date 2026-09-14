import AppKit
import SwiftUI
import CryptoKit

func verify(_ condition: @autoclosure () -> Bool, _ message: String = "Assertion", line: Int = #line) {
    if !condition() { fputs("FAIL at line \(line): \(message)\n", stderr); exit(1) }
}
let app = NSApplication.shared
let root = URL(fileURLWithPath: CommandLine.arguments[1])
let dark = CommandLine.arguments.contains("dark")
app.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
let clipboard = ClipboardStore(retention: 10, storageURL: root.appendingPathComponent("clipboard.sqlite"), encryptionKey: SymmetricKey(size: .bits256))
let usage = UsageStore(url: root.appendingPathComponent("usage.sqlite"))
let notes = NotesStore(directory: root.appendingPathComponent("Notes"))
var actions: [String] = []
let model = LauncherModel(index: AppIndex(), clipboard: clipboard, notes: notes, config: Preferences(), usage: usage) { action in
    if case .create(let value) = action { actions.append(value) }
}
model.sections = [ResultSection(title: "Notes", rows: [.newNote("first"), .newNote("second")])]
model.activate(rowID: "newnote:second")
verify(actions == ["second\n"])
model.sections = [ResultSection(title: "Notes", rows: [.newNote("first")])]
model.activate(rowID: "newnote:second")
verify(actions.count == 1, "Stale click must not activate index zero")
let old = ResultRow.app(AppEntry(id: "fixture", name: "Screen Sharing", url: URL(fileURLWithPath: "/System/Applications/Utilities/Screen Sharing.app"), lastUsed: nil))
let updated = ResultRow.app(AppEntry(id: "fixture", name: "Screen Sharing", url: URL(fileURLWithPath: "/System/Applications/Utilities/Screen Sharing.app"), lastUsed: Date()))
verify(old != updated && old.id == updated.id, "Metadata changes retain row identity")
model.sections = [ResultSection(title: "Applications", rows: [updated, .newNote("other")])]
model.selection = 1
verify(old.id != model.selectedRow?.id, "Stale app value must not inherit first-row highlight")
let a = ResultRow.snippet(Snippet(name: "One", keyword: "", body: "A"))
let b = ResultRow.snippet(Snippet(name: "Two", keyword: "", body: "B"))
verify(a.id != b.id, "Imported snippets without keywords have distinct identities")
model.sections = [ResultSection(title: "Duplicates", rows: [a, a, b])]
verify(model.rows.count == 2, "Duplicate identities are removed before rendering")
let search = FuzzyMatcher.score(query: "screen", candidate: "Screen Sharing")
verify(search != nil)
verify(AppIndex.isUserFacingApp("/System/Applications/Utilities/Screen Sharing.app"))
// Actual launcher view, fictional snippet data; no filesystem/contact search or real clipboard mutation.
var config = Preferences()
config.snippets = [Snippet(name: "Screen sharing steps", keyword: "", body: "Connect to the test Mac."), Snippet(name: "Screen recording checklist", keyword: "", body: "Use fictional data.")]
model.config = config; model.query = "snip screen"
let host = NSHostingView(rootView: LauncherView(model: model, agents: model.agents).background(Color(nsColor: .windowBackgroundColor)))
let window = NSWindow(contentRect: NSRect(origin: .zero, size: LauncherPanel.size), styleMask: [.titled], backing: .buffered, defer: false)
window.appearance = app.appearance; window.contentView = host; window.makeKeyAndOrderFront(nil)
RunLoop.main.run(until: Date().addingTimeInterval(0.5))
verify(window.firstResponder is NSTextView, "Search obtains initial editing focus")
window.makeFirstResponder(nil)
model.searchFocusRequest = UUID()
RunLoop.main.run(until: Date().addingTimeInterval(0.5))
verify(window.firstResponder is NSTextView, "Summon request restores editing focus")
host.layoutSubtreeIfNeeded()
let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds)!
host.cacheDisplay(in: host.bounds, to: rep)
try rep.representation(using: .jpeg, properties: [.compressionFactor: 0.75])!.write(to: URL(fileURLWithPath: "/tmp/volant-launcher-\(dark ? "dark" : "light").jpg"))
window.orderOut(nil)
print("PASS: launcher row identity, stale click, snippet identity, Screen Sharing eligibility, and native focus restoration")

// Real non-activating panel: route actual in-process key and mouse events without opening an app.
var launched: [String] = []
let screenApp = AppEntry(id: "/System/Applications/Utilities/Screen Sharing.app", name: "Screen Sharing", url: URL(fileURLWithPath: "/System/Applications/Utilities/Screen Sharing.app"), lastUsed: Date())
let appIndex = AppIndex(entries: [screenApp], launch: { launched.append($0.id) })
let panel = LauncherPanel(index: appIndex, clipboard: clipboard, notes: notes, config: Preferences(), usage: usage, onNote: { _ in })
panel.model.searchesSecondarySources = false
panel.toggle()
RunLoop.main.run(until: Date().addingTimeInterval(0.4))
verify(panel.isKeyWindow, "Actual launcher becomes key")
verify(panel.firstResponder is NSTextView, "Actual launcher has an editing responder")
for character in "screen" {
    let value = String(character)
    let event = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: panel.windowNumber, context: nil, characters: value, charactersIgnoringModifiers: value, isARepeat: false, keyCode: UInt16(KeyCombo.keyCodes[value]!))!
    panel.sendEvent(event)
}
RunLoop.main.run(until: Date().addingTimeInterval(0.3))
verify(panel.model.query == "screen", "Actual panel receives typed screen")
verify(panel.model.rows.first?.id == "app:" + screenApp.id)
for type in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
    let event = NSEvent.mouseEvent(with: type, location: NSPoint(x: 180, y: LauncherPanel.size.height - 110), modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: panel.windowNumber, context: nil, eventNumber: 1, clickCount: 1, pressure: type == .leftMouseDown ? 1 : 0)!
    panel.sendEvent(event)
    RunLoop.main.run(until: Date().addingTimeInterval(0.1))
}
verify(launched == [screenApp.id], "Actual result button launches the clicked app")
verify(!panel.isVisible)
panel.toggle()
RunLoop.main.run(until: Date().addingTimeInterval(0.3))
verify(panel.firstResponder is NSTextView, "Reopened panel restores keyboard focus")
panel.orderOut(nil)
let modal = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 200, height: 100), styleMask: [.titled], backing: .buffered, defer: false)
let session = app.beginModalSession(for: modal)
_ = app.runModalSession(session)
verify(app.modalWindow != nil)
panel.toggle()
verify(!panel.isVisible, "Modal session cannot leave a dead launcher visible")
app.endModalSession(session); modal.orderOut(nil)
print("PASS: real LauncherPanel screen typing, result mouse activation, repeat summon, and modal-session guard")
