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
var chatRequests = 0
var settingsRequests = 0
var chatConfig: AIConfiguration?
var panel: LauncherPanel!
panel = LauncherPanel(index: index, clipboard: clipboard, notes: NotesStore(directory: root.appendingPathComponent("Notes")), config: preferences, usage: UsageStore(url: root.appendingPathComponent("actions-usage.sqlite")), positionStore: UserDefaults(suiteName: "volant.actions.fixture")!) { action in
    switch action {
    case .ai:
        chatRequests += 1
        if !panel.model.acp.openChat(configuration: chatConfig, connect: { panel.model.acp.state.phase = "ready"; panel.model.acp.state.status = "Connected" }) {
            settingsRequests += 1; panel.orderOut(nil)
        }
    case .aiSettings: settingsRequests += 1; panel.orderOut(nil)
    default: break
    }
}
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
func render(_ name: String, view supplied: NSView? = nil) throws {
    let view = supplied ?? panel.contentView!
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
var point = NSPoint(x: LauncherPanel.size.width - 175, y: 48 + 40 + 9 + min(285, LauncherPanel.size.height - 150) - 18)
func mouse(_ type: NSEvent.EventType) -> NSEvent {
    NSEvent.mouseEvent(with: type, location: point, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                      windowNumber: panel.windowNumber, context: nil, eventNumber: 1, clickCount: 1, pressure: 0)!
}
func clickPoint() {
app.postEvent(mouse(.leftMouseUp), atStart: true)
panel.sendEvent(mouse(.leftMouseDown))
if let release = app.nextEvent(matching: .leftMouseUp, until: .distantPast, inMode: .default, dequeue: true) { panel.sendEvent(release) }
settle()
}
clickPoint()
verify(copied == ["Fixture", "Fixture"] && launched == 0, "Native mouse click executes filtered action")
panel.orderOut(nil)
print("PASS: native action search, keyboard navigation, empty state, Escape, copying, and Favorites")

// Entering AI Chat invokes setup routing, never a real provider in the fixture.
panel.toggle(); panel.model.presentAIChat(); settle()
verify(settingsRequests == 1 && !panel.isVisible, "Unconfigured AI Chat routes to Settings")
chatConfig = AIConfiguration(); chatConfig?.provider = "claude"
panel.toggle(); panel.model.presentAIChat(); settle()
verify(panel.model.acp.state.phase == "ready" && panel.model.acp.project.isEmpty, "Configured AI Chat automatically connects without a project")
verify(panel.firstResponder is NSTextView, "Chat prompt receives focus")
(panel.firstResponder as? NSTextView)?.insertText("A fictional question", replacementRange: NSRange(location: NSNotFound, length: 0)); settle()
if panel.model.acp.draft != "A fictional question" || panel.model.query != "ai" {
    try render("chat-focus-failure")
    print("Chat focus diagnostic: draft length \(panel.model.acp.draft.count), query length \(panel.model.query.count), presented \(panel.model.showingACP)")
}
verify(panel.model.acp.draft == "A fictional question" && panel.model.query == "ai", "Typing edits the chat prompt instead of launcher search")
key("\r", 36)
verify(panel.model.acp.draft.contains("\n"), "Return inserts a newline in the native prompt")
let draftBeforeUndo = panel.model.acp.draft
(panel.firstResponder as? NSTextView)?.undoManager?.undo(); settle()
// AppKit may coalesce adjacent typing into one undo group; the binding must follow the actual editor.
verify(panel.model.acp.draft != draftBeforeUndo && panel.model.acp.draft == (panel.firstResponder as? NSTextView)?.string, "Undo updates the chat draft binding")
panel.model.acp.draft = "A fictional question"; settle()
key("\r", 36, .command)
verify(panel.model.acp.submitting, "Command Return submits through the native chat editor")
// The fixture has no XPC connection; reset the local submitting flag without sending a real prompt.
panel.model.acp.submitting = false
try render("chat")
panel.orderOut(nil); settle(); panel.toggle(); settle()
(panel.firstResponder as? NSTextView)?.insertText("!", replacementRange: NSRange(location: NSNotFound, length: 0)); settle()
verify(panel.model.acp.draft.contains("!") && panel.model.query == "ai", "Reopening active chat restores prompt focus and preserves draft")
point = NSPoint(x: 20, y: LauncherPanel.size.height - 18)
clickPoint()
verify(!panel.model.showingACP && panel.model.acp.active && !panel.model.acp.draft.isEmpty, "Back returns to search without ending chat or discarding its draft")
try render("chat-back")
panel.orderOut(nil)
let settings = SettingsWindowController(configURL: panel.model.actionConfigURL, acp: panel.model.acp) {}
try chatConfig!.save(at: panel.model.actionConfigURL)
settings.state.section = "AI"
settings.window!.setContentSize(NSSize(width: 680, height: 500))
settings.showWindow(nil); settle()
try render("ai-settings-active", view: settings.window!.contentView!)
panel.model.acp.state.phase = "disconnected"
settle()
try render("ai-settings", view: settings.window!.contentView!)
settings.window!.orderOut(nil)
print("PASS: AI Chat setup routing, automatic general-chat connection, prompt focus, and active-draft preservation")
