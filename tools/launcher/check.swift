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

// A new query must select its own first result, not the prior suggestion's identity.
let home = AppEntry(id: "fixture-home", name: "Home", url: URL(fileURLWithPath: "/System/Applications/Home.app"), lastUsed: Date(timeIntervalSince1970: 1))
let assistant = AppEntry(id: "fixture-assistant", name: "Home Assistant", url: URL(fileURLWithPath: "/Applications/Home Assistant.app"), lastUsed: Date())
var homeLaunches: [String] = []
let homeIndex = AppIndex(entries: [home, assistant], launch: { homeLaunches.append($0.id) })
let homeUsage = UsageStore(url: root.appendingPathComponent("home-\(dark ? "dark" : "light").sqlite"))
let homePanel = LauncherPanel(index: homeIndex, clipboard: clipboard, notes: notes, config: Preferences(), usage: homeUsage, onNote: { _ in })
homePanel.model.searchesSecondarySources = false
homePanel.toggle()
homePanel.model.promotedHarness = "all" // Render the strip without connecting to any real harness.
RunLoop.main.run(until: Date().addingTimeInterval(0.3))
verify(homePanel.model.selectedRow?.id == "app:" + assistant.id, "Fixture begins with Home Assistant as the recent suggestion")
func sendHomeKey(_ characters: String, code: UInt16) {
    let event = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: homePanel.windowNumber, context: nil, characters: characters, charactersIgnoringModifiers: characters, isARepeat: false, keyCode: code)!
    homePanel.sendEvent(event)
    RunLoop.main.run(until: Date().addingTimeInterval(0.1))
}
// Check pixels away from text/icons: model assertions alone missed stale row styling.
func verifyHomeHighlight(firstSelected: Bool) {
    let content = homePanel.contentView!
    content.layoutSubtreeIfNeeded()
    let bitmap = content.bitmapImageRepForCachingDisplay(in: content.bounds)!
    content.cacheDisplay(in: content.bounds, to: bitmap)
    let scale = CGFloat(bitmap.pixelsHigh) / content.bounds.height
    func brightness(_ y: CGFloat) -> CGFloat {
        let color = bitmap.colorAt(x: bitmap.pixelsWide / 2, y: Int(y * scale))!.usingColorSpace(.deviceRGB)!
        return (color.redComponent + color.greenComponent + color.blueComponent) / 3
    }
    let difference = brightness(148) - brightness(190)
    let expectedSign: CGFloat = (firstSelected == dark) ? 1 : -1
    verify(difference * expectedSign > 0.025, "Rendered highlight agrees with selection in both appearances")
}
for text in ["h", "o", "m"] {
    sendHomeKey(text, code: UInt16(KeyCombo.keyCodes[text]!))
    verify(homePanel.model.rows.first?.id == "app:" + home.id, "Home ranks first for each query prefix")
    verify(homePanel.model.selection == 0, "New query selects visible first result, not prior suggestion")
    verifyHomeHighlight(firstSelected: true)
}
sendHomeKey(String(UnicodeScalar(NSDownArrowFunctionKey)!), code: 125)
verify(homePanel.model.selectedRow?.id == "app:" + assistant.id, "Down selects Home Assistant")
verifyHomeHighlight(firstSelected: false)
sendHomeKey(String(UnicodeScalar(NSUpArrowFunctionKey)!), code: 126)
verify(homePanel.model.selectedRow?.id == "app:" + home.id, "Up returns to Home")
verify(homePanel.model.query == "hom", "Navigation does not rewrite the query")
verifyHomeHighlight(firstSelected: true)
if let content = homePanel.contentView, let bitmap = content.bitmapImageRepForCachingDisplay(in: content.bounds) {
    content.cacheDisplay(in: content.bounds, to: bitmap)
    try bitmap.representation(using: .jpeg, properties: [.compressionFactor: 0.75])!.write(to: URL(fileURLWithPath: "/tmp/volant-home-\(dark ? "dark" : "light").jpg"))
}
for type in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
    homePanel.sendEvent(NSEvent.mouseEvent(with: type, location: NSPoint(x: 180, y: LauncherPanel.size.height - 148), modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: homePanel.windowNumber, context: nil, eventNumber: 2, clickCount: 1, pressure: type == .leftMouseDown ? 1 : 0)!)
    RunLoop.main.run(until: Date().addingTimeInterval(0.1))
}
verify(homeLaunches == [home.id], "Clicking Home above Home Assistant activates Home with pinned harness visible")
print("PASS: h/ho/hom initial selection, up/down navigation, and Home mouse activation with pinned harness")


// Volume uses fictional hardware; native Return exercises routing without changing host audio.
final class LauncherAudioFixture: AudioHardwareAccess {
    var value: Float32 = 0.35
    var muted = false
    var supported = true
    var available = true
    func output() throws -> AudioOutputState {
        guard available else { throw VolumeFailure(message: "No audio output is available. Connect an output and try again.") }
        return AudioOutputState(device: 1, name: "Fixture Speakers", volumes: [(0, value)], canSetVolume: supported, muted: muted, canSetMute: supported)
    }
    func setVolume(_ value: Float32, channel: UInt32, device: UInt32) throws { self.value = value }
    func setMute(_ value: Bool, device: UInt32) throws { muted = value }
}
let audioFixture = LauncherAudioFixture()
homePanel.model.volumeControl = VolumeControl(hardware: audioFixture)
homePanel.toggle()
homePanel.model.query = "volume"
RunLoop.main.run(until: Date().addingTimeInterval(0.3))
verify(homePanel.model.rows.count == 3, "Volume command discovery")
func captureVolume(_ suffix: String) throws {
    RunLoop.main.run(until: Date().addingTimeInterval(0.2))
    let content = homePanel.contentView!
    content.layoutSubtreeIfNeeded()
    let bitmap = content.bitmapImageRepForCachingDisplay(in: content.bounds)!
    content.cacheDisplay(in: content.bounds, to: bitmap)
    try bitmap.representation(using: .jpeg, properties: [.compressionFactor: 0.75])!.write(to: URL(fileURLWithPath: "/tmp/volant-volume-\(suffix)-\(dark ? "dark" : "light").jpg"))
}
try captureVolume("commands")
sendHomeKey("\r", code: 36)
verify(abs(audioFixture.value - 0.4) < 0.001 && homePanel.isVisible, "Return adjusts volume and keeps panel open")
verify(homePanel.model.actionFeedback?.contains("40%") == true, "Show actual volume readback")
homePanel.model.query = "volume 65%"
sendHomeKey("\r", code: 36)
verify(abs(audioFixture.value - 0.65) < 0.001, "Exact volume via native Return")
try captureVolume("applied")
homePanel.model.query = "mute"
sendHomeKey("\r", code: 36)
verify(audioFixture.muted, "Native mute command")
homePanel.model.query = "unmute"
sendHomeKey("\r", code: 36)
verify(!audioFixture.muted, "Native unmute command")
audioFixture.supported = false
homePanel.model.query = "volume"
sendHomeKey("\r", code: 36)
verify(homePanel.model.actionFeedback?.contains("doesn’t support") == true, "Unsupported hardware shows an actionable error")
if case .volume(_, let detail) = homePanel.model.rows[0] {
    verify(detail == "Hardware control only", "Unsupported control detail updates")
} else { verify(false, "Volume result expected") }
try captureVolume("unsupported")
homePanel.model.query = "volume 101"
verify(homePanel.model.rows.isEmpty && homePanel.model.notice != nil, "Invalid percentage has no action")
audioFixture.available = false
homePanel.model.query = "volume"
verify(homePanel.model.rows.isEmpty && homePanel.model.notice?.contains("No audio output") == true, "Missing output state")
try captureVolume("missing")
homePanel.orderOut(nil)
print("PASS: native volume discovery, Return, exact level, mute/unmute, unsupported and missing output")
