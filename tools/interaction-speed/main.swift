import AppKit
import CryptoKit
import VolantCore

setbuf(stdout, nil)
let application = NSApplication.shared
application.setActivationPolicy(.regular)
let root = URL(fileURLWithPath: CommandLine.arguments[1])
let count = Int(CommandLine.arguments[2])!
let idle = Double(CommandLine.arguments[3])! / 1000
let clipboard = ClipboardStore(retention: 1, storageURL: root.appendingPathComponent("clipboard.sqlite"), encryptionKey: SymmetricKey(size: .bits256))
let notes = NotesStore(directory: root.appendingPathComponent("Notes"))
let defaults = UserDefaults(suiteName: "volant.interaction.fixture." + UUID().uuidString)!
var launches = [false: 0, true: 0]
let entry = AppEntry(id: "fictional-screen-app", name: "Screen Fixture", url: URL(fileURLWithPath: "/System/Applications/Utilities/Screen Sharing.app"), lastUsed: Date())
var panels: [Bool: LauncherPanel] = [:]
for prepare in [false, true] {
    let index = AppIndex(entries: [entry], launch: { app in
        precondition(app.id == entry.id)
        launches[prepare, default: 0] += 1
    })
    let usage = UsageStore(url: root.appendingPathComponent("usage-\(prepare).sqlite"))
    let panel = LauncherPanel(index: index, clipboard: clipboard, notes: notes, config: Preferences(), usage: usage, positionStore: defaults, preparesWhenHidden: prepare, onNote: { _ in })
    panel.model.searchesSecondarySources = false
    panels[prepare] = panel
}
func require(_ condition: @autoclosure () -> Bool, _ message: String) {
    guard condition() else { fputs(message + "\n", stderr); exit(2) }
}
func pump(_ seconds: Double) { RunLoop.main.run(until: Date().addingTimeInterval(seconds)) }
func key(_ value: String, code: UInt16, panel: LauncherPanel) {
    let event = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: panel.windowNumber, context: nil, characters: value, charactersIgnoringModifiers: value, isARepeat: false, keyCode: code)!
    panel.sendEvent(event)
}
print("mode,cycle,kind,handler_to_editor_ready_ms,first_key_delivery_ms,launches")
for cycle in 0...count {
    // Alternate the order to avoid always favoring the second panel/cache user.
    for prepare in cycle.isMultiple(of: 2) ? [false, true] : [true, false] {
        let panel = panels[prepare]!
        let started = ProcessInfo.processInfo.systemUptime
        panel.toggle()
        require(panel.isKeyWindow && panel.firstResponder is NSTextView, "Editor was not ready synchronously")
        let ready = ProcessInfo.processInfo.systemUptime
        key("s", code: UInt16(KeyCombo.keyCodes["s"]!), panel: panel)
        require(panel.model.query == "s", "First key was lost or appended to stale text")
        let typed = ProcessInfo.processInfo.systemUptime
        for character in "creen" { key(String(character), code: UInt16(KeyCombo.keyCodes[String(character)]!), panel: panel) }
        require(panel.model.query == "screen" && panel.model.selectedRow?.id == "app:" + entry.id, "Search did not select the fixture application")
        pump(0.02)
        require(panel.model.query == "screen", "Deferred focus/layout overwrote typed text")
        let previous = launches[prepare, default: 0]
        key("\r", code: 36, panel: panel)
        let deadline = Date().addingTimeInterval(2)
        while launches[prepare, default: 0] == previous && Date() < deadline { pump(0.005) }
        require(launches[prepare] == previous + 1 && !panel.isVisible, "Return did not launch the fixture and dismiss")
        print("\(prepare ? "prepared" : "baseline"),\(cycle),\(cycle == 0 ? "initial" : "reopen"),\(String(format: "%.3f", (ready - started) * 1000)),\(String(format: "%.3f", (typed - ready) * 1000)),\(launches[prepare]!)")
        pump(idle)
        require(!panel.isVisible && !panel.isKeyWindow, "Hidden preparation showed or focused the panel")
    }
}
