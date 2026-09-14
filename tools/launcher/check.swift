import AppKit
import SwiftUI
import CryptoKit

func verify(_ condition: @autoclosure () -> Bool, _ message: String = "Assertion", line: Int = #line) {
    if !condition() { fputs("FAIL at line \(line): \(message)\n", stderr); exit(1) }
}
let positionDefaults = UserDefaults(suiteName: "volant.launcher.test." + UUID().uuidString)!
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
let panel = LauncherPanel(index: appIndex, clipboard: clipboard, notes: notes, config: Preferences(), usage: usage, positionStore: positionDefaults, onNote: { _ in })
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
let homePanel = LauncherPanel(index: homeIndex, clipboard: clipboard, notes: notes, config: Preferences(), usage: homeUsage, positionStore: positionDefaults, onNote: { _ in })
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

final class RoutingFixture: AudioRouting {
    var output = "speakers"
    var input = "microphone"
    var connected = true
    var writes = 0
    func routes() throws -> [AudioRoute] {
        var result = [AudioRoute(uid: "speakers", device: 1, name: "Mac Speakers", direction: .output, current: output == "speakers"), AudioRoute(uid: "microphone", device: 2, name: "Mac Microphone", direction: .input, current: input == "microphone")]
        if connected {
            result += [AudioRoute(uid: "airpods", device: 3, name: "AirPods", direction: .output, current: output == "airpods"), AudioRoute(uid: "airpods", device: 3, name: "AirPods", direction: .input, current: input == "airpods")]
        }
        return result
    }
    func select(_ route: AudioRoute) throws {
        guard try routes().contains(where: { $0.id == route.id }) else { throw VolumeFailure(message: "This audio device disconnected. Refresh the list and try again.") }
        writes += 1
        if route.direction == .output { output = route.uid } else { input = route.uid }
    }
}
let routingFixture = RoutingFixture()
homePanel.model.audioRouting = routingFixture
homePanel.toggle()
homePanel.model.query = "audio"
RunLoop.main.run(until: Date().addingTimeInterval(0.3))
verify(homePanel.model.rows.count == 4 && Set(homePanel.model.rows.map(\.id)).count == 4, "Input/output identities stay distinct")
try captureVolume("audio-devices")
homePanel.model.query = "output air"
sendHomeKey("\r", code: 36)
verify(routingFixture.output == "airpods" && routingFixture.input == "microphone", "Changing output leaves microphone alone")
verify(homePanel.model.rows.first?.kind == "Current", "Current marker updates after switching")
try captureVolume("audio-selected")
homePanel.model.query = "input air"
sendHomeKey("\r", code: 36)
verify(routingFixture.input == "airpods", "Input switching is independent")
homePanel.model.query = "audio output air"
let routeWrites = routingFixture.writes
routingFixture.connected = false
sendHomeKey("\r", code: 36)
verify(routingFixture.writes == routeWrites && homePanel.model.actionFeedback?.contains("disconnected") == true, "Disconnected selection does not fall back to another device")
try captureVolume("audio-disconnected")
homePanel.model.query = "audio missing"
verify(homePanel.model.rows.isEmpty && homePanel.model.notice != nil, "No matching audio devices")
verify(AudioRouteQuery("audiobook") == nil, "Audio command does not hijack unrelated names")
for command in ["audio", "input", "output"] { verify(LauncherRouting.isReserved(command), "Audio command reserved for import") }
homePanel.orderOut(nil)
print("PASS: native audio route listing, output/input independence, current marker, disconnect, empty search")

final class ConnectivityFixture: ConnectivityAccess {
    var delayed = false
    var callback: ((ConnectivitySnapshot) -> Void)?
    var joins = 0
    var completion: ((String?) -> Void)?
    let secured = WiFiChoice(ssid: Data("Studio".utf8), name: "Studio Wi-Fi", security: "WPA2 Personal", signal: -52, current: false)
    func load(_ source: String, refresh: Bool, completion: @escaping (ConnectivitySnapshot) -> Void) {
        callback = completion
        if delayed { return }
        if source == "bluetooth" {
            completion(ConnectivitySnapshot(items: [.bluetooth(id: "fixture-headphones", name: "Studio Headphones"), .bluetooth(id: "fixture-keyboard", name: "Desk Keyboard"), .settings("bluetooth")], message: nil))
        } else {
            completion(ConnectivitySnapshot(items: [.wifi(WiFiChoice(ssid: Data("Home".utf8), name: "Home Wi-Fi", security: "WPA3 Personal", signal: -35, current: true)), .wifi(secured), .settings("wifi")], message: nil))
        }
    }
    func join(_ network: WiFiChoice, password: String?, useSaved: Bool, completion: @escaping (String?) -> Void) {
        joins += 1
        self.completion = completion
    }
}
let connectivityFixture = ConnectivityFixture()
homePanel.model.connectivity = connectivityFixture
homePanel.toggle()
homePanel.model.query = "bluetooth"
RunLoop.main.run(until: Date().addingTimeInterval(0.2))
verify(homePanel.model.rows.count == 3, "Connected Bluetooth list")
try captureVolume("bluetooth")
homePanel.model.query = "wifi"
RunLoop.main.run(until: Date().addingTimeInterval(0.2))
verify(homePanel.model.rows.count == 3, "Wi-Fi network list")
try captureVolume("wifi")
homePanel.model.query = "wifi studio"
sendHomeKey("\r", code: 36)
verify(homePanel.model.wifiJoin?.id == connectivityFixture.secured.id && connectivityFixture.joins == 0, "Secured network opens password form without joining")
RunLoop.main.run(until: Date().addingTimeInterval(0.2))
verify((homePanel.firstResponder as? NSTextView)?.isFieldEditor == true, "Password form gets a native editing responder")
try captureVolume("wifi-password")
for letter in "fixture" { sendHomeKey(String(letter), code: UInt16(KeyCombo.keyCodes[String(letter)]!)) }
sendHomeKey("\r", code: 36)
verify(connectivityFixture.joins == 1, "Native secure field Return submits exactly one join")
connectivityFixture.completion?("Incorrect fixture password")
RunLoop.main.run(until: Date().addingTimeInterval(0.2))
sendHomeKey(String(UnicodeScalar(27)!), code: 53)
verify(homePanel.model.wifiJoin == nil && homePanel.isVisible, "Escape cancels password entry, not the launcher")
homePanel.model.joinWiFi(connectivityFixture.secured, password: "fictional-fixture", useSaved: false)
homePanel.model.joinWiFi(connectivityFixture.secured, password: "fictional-fixture", useSaved: false)
verify(connectivityFixture.joins == 2, "Duplicate joins are rejected")
connectivityFixture.completion?("Incorrect fixture password")
verify(!homePanel.model.connectivityBusy && homePanel.model.actionFeedback == "Incorrect fixture password", "Joining error remains visible")
connectivityFixture.delayed = true
homePanel.model.query = "wifi"
let stale = connectivityFixture.callback
homePanel.model.query = "output"
stale?(ConnectivitySnapshot(items: [.settings("wifi")], message: "Old scan"))
verify(homePanel.model.rows.allSatisfy { if case .audioRoute = $0 { return true }; return false }, "Old scans cannot overwrite a newer query")
homePanel.model.query = "wifi"
connectivityFixture.callback?(ConnectivitySnapshot(items: [.settings("wifi")], message: "Location access is off. Enable Volant in System Settings → Privacy & Security → Location Services."))
try captureVolume("wifi-denied")
homePanel.orderOut(nil)
print("PASS: connectivity lists, password form, cancel, duplicate joins, errors, stale scan rejection, denied state")


// A real key-window transfer must preserve a live conversation and unsent input.
let sticky = LauncherPanel(index: AppIndex(), clipboard: clipboard, notes: notes, config: Preferences(), usage: usage, positionStore: positionDefaults, onNote: { _ in })
sticky.model.searchesSecondarySources = false
sticky.model.query = "acp"
sticky.model.acp.state.phase = "working"
sticky.model.acp.state.sessionID = "fictional-session"
sticky.model.acp.draft = "Keep this fictional draft"
sticky.toggle()
RunLoop.main.run(until: Date().addingTimeInterval(0.3))
let otherWindow = NSWindow(contentRect: NSRect(x: 20, y: 20, width: 180, height: 100), styleMask: [.titled], backing: .buffered, defer: false)
for phase in ["starting", "working", "cancelling", "ready"] {
    sticky.model.acp.state.phase = phase
    otherWindow.makeKeyAndOrderFront(nil)
    RunLoop.main.run(until: Date().addingTimeInterval(0.1))
    verify(sticky.isVisible && !sticky.isKeyWindow, "ACP remains visible after real focus loss in \(phase)")
    sticky.toggle()
    verify(sticky.isVisible && sticky.isKeyWindow, "Summon refocuses a visible conversation")
}
sticky.cancelOperation(nil)
verify(!sticky.isVisible && sticky.model.acp.state.sessionID == "fictional-session", "Explicit dismissal keeps the ACP session")
sticky.toggle()
RunLoop.main.run(until: Date().addingTimeInterval(0.2))
verify(sticky.model.query == "acp" && sticky.model.acp.draft == "Keep this fictional draft", "Reopening preserves conversation and draft")
sticky.model.acp.state.phase = "disconnected"
otherWindow.makeKeyAndOrderFront(nil)
verify(sticky.isVisible, "Unsent ACP draft survives focus loss")
sticky.toggle()
sticky.model.acp.draft = ""
sticky.model.query = "screen"
otherWindow.makeKeyAndOrderFront(nil)
verify(!sticky.isVisible, "Ordinary launcher search still dismisses on blur")
otherWindow.orderOut(nil)

// Native movement notifications save the position; re-summon does not recenter it.
sticky.toggle()
RunLoop.main.run(until: Date().addingTimeInterval(0.2))
let screenFrame = NSScreen.main!.visibleFrame
let movedOrigin = NSPoint(x: screenFrame.minX + 24, y: screenFrame.minY + 36)
sticky.setFrameOrigin(movedOrigin)
RunLoop.main.run(until: Date().addingTimeInterval(0.1))
verify(positionDefaults.dictionary(forKey: "launcherPosition") != nil, "Window move saves position")
sticky.orderOut(nil)
sticky.toggle()
RunLoop.main.run(until: Date().addingTimeInterval(0.2))
verify(sticky.frame.origin == movedOrigin, "Re-summon keeps the moved position")
sticky.orderOut(nil)
positionDefaults.set(["x": 100000.0, "y": 100000.0], forKey: "launcherPosition")
sticky.toggle()
RunLoop.main.run(until: Date().addingTimeInterval(0.2))
verify(NSScreen.screens.contains { $0.visibleFrame.contains(sticky.frame) }, "Offscreen saved position is recovered onto a visible display")
sticky.orderOut(nil)
print("PASS: actual ACP focus loss/refocus, explicit dismissal, draft preservation, ordinary blur, saved placement, and offscreen recovery")

// App binding writes preserve nested unknown fields and reject conflicts/stale editors.
let bindingURL = root.appendingPathComponent("binding-config.json")
let bindingBytes = Data(#"{"future":{"keep":true},"aliases":{"other":"/Other.app","old":"/Test.app"},"appHotKeys":[{"bundleIdentifier":"test.app","hotKey":"ctrl+option+t","future":42}]}"#.utf8)
try bindingBytes.write(to: bindingURL)
try AppBindingStore.save(bundleID: "test.app", path: "/Test.app", originalAlias: "old", alias: "t", hotKey: "ctrl+option+y", expected: bindingBytes, at: bindingURL, available: { _ in true })
let changed = try Data(contentsOf: bindingURL)
let bindingObject = try JSONSerialization.jsonObject(with: changed) as! [String: Any]
verify((bindingObject["future"] as? [String: Bool])?["keep"] == true)
verify((bindingObject["appHotKeys"] as? [[String: Any]])?.first?["future"] as? Int == 42)
let bindingConfig = try JSONDecoder().decode(Preferences.self, from: changed)
verify(bindingConfig.aliases["old"] == nil && bindingConfig.aliases["t"] == "/Test.app" && bindingConfig.aliases["other"] == "/Other.app")
for (alias, shortcut, stale, available) in [("other", "ctrl+option+y", false, true), ("settings", "ctrl+option+y", false, true), ("t", "c", false, true), ("t", "option+space", false, true), ("t", "ctrl+option+y", true, true), ("t", "ctrl+option+y", false, false)] {
    do {
        try AppBindingStore.save(bundleID: "test.app", path: "/Test.app", originalAlias: "t", alias: alias, hotKey: shortcut, expected: stale ? bindingBytes : changed, at: bindingURL, available: { _ in available })
        verify(false, "Invalid binding must fail")
    } catch { verify(try! Data(contentsOf: bindingURL) == changed, "Failed edit preserves file") }
}
try AppBindingStore.save(bundleID: "test.app", path: "/Test.app", originalAlias: "t", alias: "", hotKey: "", expected: changed, at: bindingURL, available: { _ in true })
let cleared = try JSONDecoder().decode(Preferences.self, from: Data(contentsOf: bindingURL))
verify(cleared.appHotKeys.isEmpty && cleared.aliases["t"] == nil && cleared.aliases["other"] != nil)
model.query = "volant settings"
verify(model.rows.first?.id == "command:settings")
model.query = "reload config"
verify(model.rows.first?.id == "command:reload")
print("PASS: app binding persistence, conflicts and launcher settings commands")

let systemSettings = AppEntry(id: "/System/Applications/System Settings.app", name: "System Settings", url: URL(fileURLWithPath: "/System/Applications/System Settings.app"), lastUsed: nil)
let settingsSearch = LauncherModel(index: AppIndex(entries: [systemSettings]), clipboard: clipboard, notes: notes, config: Preferences(), usage: usage, onNote: { _ in })
settingsSearch.searchesSecondarySources = false
for query in ["sett", "Settings", " SETTINGS "] {
    settingsSearch.query = query
    verify(settingsSearch.rows.map(\.id) == ["app:" + systemSettings.id, "command:settings"], "Apps precede Volant commands")
    verify(settingsSearch.selectedRow?.id == "app:" + systemSettings.id, "System Settings starts selected")
}
settingsSearch.query = "volant settings"
verify(settingsSearch.rows.map(\.id) == ["command:settings"], "Explicit Volant Settings stays direct")
print("PASS: Settings search prioritizes System Settings over Volant Settings")

let globalURL = root.appendingPathComponent("global-shortcuts.json")
let globalBytes = Data(#"{"summonHotKey":"option+space","notesHotKey":"option+n","unknown":{"keep":true},"appHotKeys":[{"bundleIdentifier":"fixture.app","hotKey":"ctrl+option+t","unknown":42}]}"#.utf8)
try globalBytes.write(to: globalURL)
try GlobalShortcutStore.save(key: "summonHotKey", value: "ctrl+option+space", expectedValue: "option+space", at: globalURL, available: { _ in true })
try GlobalShortcutStore.save(key: "notesHotKey", value: "ctrl+option+n", expectedValue: "option+n", at: globalURL, available: { _ in true })
let globalSaved = try Data(contentsOf: globalURL)
let globalConfig = try JSONDecoder().decode(Preferences.self, from: globalSaved)
verify(globalConfig.summonHotKey == "ctrl+option+space" && globalConfig.notesHotKey == "ctrl+option+n")
let globalObject = try JSONSerialization.jsonObject(with: globalSaved) as! [String: Any]
verify((globalObject["unknown"] as? [String: Bool])?["keep"] == true)
verify((globalObject["appHotKeys"] as? [[String: Any]])?.first?["unknown"] as? Int == 42)
for (value, expected, available) in [("ctrl+option+n", "ctrl+option+space", true), ("ctrl+option+t", "ctrl+option+space", true), ("space", "ctrl+option+space", true), ("ctrl+option+y", "option+space", true), ("ctrl+option+y", "ctrl+option+space", false)] {
    do {
        try GlobalShortcutStore.save(key: "summonHotKey", value: value, expectedValue: expected, at: globalURL, available: { _ in available })
        verify(false, "Conflicting or stale global shortcut must fail")
    } catch { verify(try! Data(contentsOf: globalURL) == globalSaved, "Failed global shortcut edit preserves file") }
}
print("PASS: global shortcut changes, conflicts, stale edits and unknown-field preservation")
