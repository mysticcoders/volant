import AppKit
import SwiftUI
import CryptoKit

setbuf(stdout, nil)
func verify(_ condition: @autoclosure () -> Bool, _ message: String) {
    guard condition() else { fputs("FAIL: \(message)\n", stderr); exit(1) }
}
let app = NSApplication.shared
app.setActivationPolicy(.regular)
let root = URL(fileURLWithPath: CommandLine.arguments[1])
let dark = CommandLine.arguments.contains("dark")
app.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
let entry = AppEntry(id: "/Applications/Fixture.app", name: "Fixture", url: URL(fileURLWithPath: "/Applications/Fixture.app"), lastUsed: Date())
var launched = 0
let index = AppIndex(entries: [entry], launch: { _ in launched += 1 })
let clipboard = ClipboardStore(retention: 2, storageURL: root.appendingPathComponent("actions-clipboard.sqlite"), encryptionKey: SymmetricKey(size: .bits256))
var preferences = Preferences()
if CommandLine.arguments.contains("compact") { preferences.appearance.scale = 0.8 }
if CommandLine.arguments.contains("large") { preferences.appearance.scale = 1.4 }
let panel = LauncherPanel(index: index, clipboard: clipboard, notes: NotesStore(directory: root.appendingPathComponent("Notes")), config: preferences, usage: UsageStore(url: root.appendingPathComponent("actions-usage.sqlite")), positionStore: UserDefaults(suiteName: "volant.actions.fixture")!) { _ in }
panel.model.searchesSecondarySources = false
panel.model.actionConfigURL = root.appendingPathComponent("actions-config.json")
try Data("{}".utf8).write(to: panel.model.actionConfigURL)
var copied: [String] = []
panel.model.copyText = { copied.append($0) }
func settle() { RunLoop.main.run(until: Date().addingTimeInterval(0.2)) }
func key(_ text: String, _ code: UInt16, _ modifiers: NSEvent.ModifierFlags = []) {
    let event = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: modifiers, timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: panel.windowNumber, context: nil, characters: text, charactersIgnoringModifiers: text, isARepeat: false, keyCode: code)!
    // NSApplication dispatches command equivalents before the window's keyDown path.
    if !modifiers.contains(.command) || !panel.performKeyEquivalent(with: event) { panel.sendEvent(event) }
    settle()
}
func render(_ name: String) throws {
    let view = panel.contentView!
    view.layoutSubtreeIfNeeded()
    let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds)!
    view.cacheDisplay(in: view.bounds, to: bitmap)
    try bitmap.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: "/tmp/volant-actions-\(name)-\(dark ? "dark" : "light")-\(preferences.appearance.scale).png"))
}
app.activate(ignoringOtherApps: true)
panel.toggle(); settle()
key("k", 40, .command)
verify(panel.model.actionTarget != nil, "Command K opens actions")
verify(panel.firstResponder is NSTextView, "Action search receives editing focus")
try render("menu")
// Rendering may end editing; explicitly restore the action field through its native control.
func fields(_ view: NSView) -> [NSTextField] { (view as? NSTextField).map { [$0] } ?? view.subviews.flatMap(fields) }
func focusActionSearch() {
    let field = fields(panel.contentView!).first { $0.placeholderString == "Search for actions…" }!
    panel.makeFirstResponder(field)
}
focusActionSearch()
for _ in 0..<8 { key(String(UnicodeScalar(NSDownArrowFunctionKey)!), 125) }
try render("more")
focusActionSearch(); key("\u{1b}", 53)
key("k", 40, .command)
focusActionSearch()
(panel.firstResponder as? NSTextView)?.insertText("copy", replacementRange: NSRange(location: NSNotFound, length: 0)); settle()
verify(panel.model.query.isEmpty, "Action search does not alter launcher query")
key(String(UnicodeScalar(NSDownArrowFunctionKey)!), 125)
key("\r", 36)
verify(copied == ["Fixture"] && launched == 0, "Filtered arrows and Return copy name without launching app")
verify(panel.model.actionTarget == nil && panel.isVisible, "Copy closes actions and keeps launcher visible")
key("k", 40, .command)
focusActionSearch()
(panel.firstResponder as? NSTextView)?.insertText("unmatched fixture", replacementRange: NSRange(location: NSNotFound, length: 0)); settle()
try render("empty")
focusActionSearch(); key("\r", 36)
verify(launched == 0 && panel.model.actionTarget != nil, "Empty menu Return cannot launch underlying app")
key("\u{1b}", 53)
verify(panel.model.actionTarget == nil && panel.isVisible, "Escape dismisses actions before launcher")
key("k", 40, .command)
focusActionSearch()
(panel.firstResponder as? NSTextView)?.insertText("favorites", replacementRange: NSRange(location: NSNotFound, length: 0)); settle()
key("\r", 36)
verify(panel.model.sections.first?.title == "Favorites", "Favorite appears in home section")
try render("favorites")
key("k", 40, .command)
focusActionSearch()
(panel.firstResponder as? NSTextView)?.insertText("copy name", replacementRange: NSRange(location: NSNotFound, length: 0)); settle()
// Native mouse activation of the filtered first row, at each supported panel size.
let point = NSPoint(x: LauncherPanel.size.width - 175, y: 48 + 40 + 9 + min(285, LauncherPanel.size.height - 150) - 18)
func mouse(_ type: NSEvent.EventType) -> NSEvent {
    NSEvent.mouseEvent(with: type, location: point, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                      windowNumber: panel.windowNumber, context: nil, eventNumber: 1, clickCount: 1, pressure: 0)!
}
app.postEvent(mouse(.leftMouseUp), atStart: true)
panel.sendEvent(mouse(.leftMouseDown))
if let release = app.nextEvent(matching: .leftMouseUp, until: .distantPast, inMode: .default, dequeue: true) { panel.sendEvent(release) }
settle()
verify(copied == ["Fixture", "Fixture"] && launched == 0, "Native mouse click executes filtered action")
panel.orderOut(nil)
print("PASS: native action search, keyboard navigation, empty state, Escape, copying, and Favorites")
