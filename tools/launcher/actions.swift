import AppKit
import SwiftUI
import CryptoKit
import VolantCore

setbuf(stdout, nil)
var currentScenario = ""

/// Stops the fixture with the failing check and the scenario it belongs to.
func verify(_ condition: @autoclosure () -> Bool, _ message: String) {
    guard condition() else { fputs("FAIL: \(message) [\(currentScenario)]\n", stderr); exit(1) }
}
let app = NSApplication.shared
app.setActivationPolicy(.regular)
let root = URL(fileURLWithPath: CommandLine.arguments[1])
let dark = CommandLine.arguments.contains("dark")
/// A translation pass from check-launcher-actions.sh, such as `language=de` with `-AppleLanguages (de)`,
/// or a layout pass from render-vm.py, `language=pseudo` or `language=pseudo-rtl` with the en-XA
/// pseudo-locale. Only scenarios whose checks don't compare English text run translated, and their
/// renders carry the language as a suffix for layout review.
let language = CommandLine.arguments.first { $0.hasPrefix("language=") }.map { String($0.dropFirst("language=".count)) }
app.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
var preferences = Preferences()
if CommandLine.arguments.contains("compact") { preferences.appearance.scale = 0.8 }
if CommandLine.arguments.contains("large") { preferences.appearance.scale = 1.4 }
/// Only the launcher panel follows the scale setting. At compact and large sizes the fixture runs only
/// the size-sensitive scenarios, and skips standalone views those scenarios render along the way.
let defaultScale = preferences.appearance.scale == 1
let positionSuite = "volant.actions.fixture." + UUID().uuidString
let launcherSearchPlaceholder = LauncherModel.defaultSearchPlaceholder
let entry = AppEntry(id: "/Applications/Fixture.app", name: "Fixture", url: URL(fileURLWithPath: "/Applications/Fixture.app"), lastUsed: Date())
let bundledExtension = Bundle.main.url(forResource: "HelloWorld", withExtension: nil)!
// A fictional solid-color WebP icon, so launcher and Settings renders show an extension icon.
let fixtureIcon = Data(base64Encoded: "UklGRh4AAABXRUJQVlA4TBEAAAAvH8AHAAdQvKIUuf+BiOh/AAA=")!

var launched = 0
var spotlightAvailable = false
var clipboardAvailable = true
var clipboardRetryDelay: TimeInterval = 0
var chatRequests = 0
var settingsRequests = 0
var extensionSettingsRequests = 0
var credentialWrites = 0
var chatConfig: AIConfiguration?
var copied: [String] = []
var index: AppIndex!
var clipboard: ClipboardStore!
var panel: LauncherPanel!
let fakeCredentials = AICredentials(read: { _ in nil }, write: { _, _ in credentialWrites += 1 })

/// Hides the previous launcher and replaces it with a fresh hidden one: new app index, encrypted
/// clipboard, usage and notes stores, an empty configuration file, and zeroed counters. Every scenario
/// starts from this, so none depends on what an earlier one created, opened or saved.
func freshLauncher() {
    panel?.orderOut(nil)
    launched = 0; spotlightAvailable = false; clipboardAvailable = true; clipboardRetryDelay = 0
    chatRequests = 0; settingsRequests = 0; extensionSettingsRequests = 0; credentialWrites = 0
    chatConfig = nil; copied = []
    let id = UUID().uuidString
    index = AppIndex(entries: [entry], launch: { _ in launched += 1 }, startQuery: { _ in spotlightAvailable })
    let clipboardKey = SymmetricKey(size: .bits256)
    clipboard = ClipboardStore(retention: 2, storageURL: root.appendingPathComponent("actions-clipboard-\(id).sqlite"), keyLoader: { _ in
        if clipboardRetryDelay > 0 { Thread.sleep(forTimeInterval: clipboardRetryDelay) }
        guard clipboardAvailable else { throw KeychainKey.Failure.access(-25308) }
        return clipboardKey
    })
    let positions = UserDefaults(suiteName: positionSuite)!
    positions.removeObject(forKey: "launcherPosition")
    panel = LauncherPanel(index: index, clipboard: clipboard, notes: NotesStore(directory: root.appendingPathComponent("Notes-\(id)")), config: preferences,
                          usage: UsageStore(url: root.appendingPathComponent("actions-usage-\(id).sqlite")), positionStore: positions,
                          files: FileSearch(startQuery: { _ in false })) { action in
        switch action {
        case .ai:
            chatRequests += 1
            if !panel.model.acp.openChat(configuration: chatConfig, connect: { panel.model.acp.state.phase = "ready"; panel.model.acp.state.status = "Connected" }) {
                settingsRequests += 1; panel.orderOut(nil)
            }
        case .aiSettings: settingsRequests += 1; panel.orderOut(nil)
        case .extensionSettings: extensionSettingsRequests += 1; panel.orderOut(nil)
        default: break
        }
    }
    panel.model.searchesSecondarySources = false
    panel.model.actionConfigURL = root.appendingPathComponent("actions-config-\(id).json")
    try! Data("{}".utf8).write(to: panel.model.actionConfigURL)
    panel.model.copyText = { copied.append($0) }
}

func settle() { RunLoop.main.run(until: Date().addingTimeInterval(0.2)) }

/// Runs the main run loop until the condition has held without interruption for `stable` seconds,
/// or until `timeout` passes. Loaded CI runners and guests can miss a fixed sleep, so focus and
/// state are polled; the stability window covers SwiftUI focus work queued for a later turn.
@discardableResult
func waitUntil(timeout: TimeInterval = 3, stable: TimeInterval = 0, _ condition: () -> Bool) -> Bool {
    let deadline = Date().addingTimeInterval(timeout)
    var heldSince: Date?
    while Date() < deadline {
        if condition() {
            let start = heldSince ?? Date()
            heldSince = start
            if Date().timeIntervalSince(start) >= stable { return true }
        } else {
            heldSince = nil
        }
        RunLoop.main.run(until: Date().addingTimeInterval(0.02))
    }
    return condition()
}

/// The text field whose native editor holds keyboard focus in the key launcher panel, if any.
func focusedField() -> NSTextField? {
    guard panel.isKeyWindow, let editor = panel.firstResponder as? NSTextView else { return nil }
    return editor.delegate as? NSTextField
}

/// Whether the AI Chat prompt editor holds keyboard focus in the key launcher panel.
func chatPromptFocused() -> Bool {
    panel.isKeyWindow && panel.firstResponder is ACPPromptView.PromptTextView
}

/// Describes keyboard focus and launcher state for failure messages.
func focusState() -> String {
    "key=\(panel.isKeyWindow), visible=\(panel.isVisible), responder=\(String(describing: panel.firstResponder)), field=\(String(describing: focusedField()?.placeholderString)), chat=\(panel.model.showingACP), query=\(panel.model.query)"
}

/// Summons the launcher and waits until its search editor holds focus, so the next key reaches it.
func summon() {
    panel.toggle()
    verify(waitUntil(stable: 0.15) { focusedField()?.placeholderString == launcherSearchPlaceholder },
           "Summoned launcher focuses search: \(focusState())")
}

/// Waits until AI Chat is showing with its prompt focused, after Tab or a resume.
func awaitChatPrompt(_ message: String) {
    verify(waitUntil(stable: 0.1) { panel.model.showingACP && chatPromptFocused() }, "\(message): \(focusState())")
}

/// Sends a key to the launcher the way NSApplication would, then lets the panel settle.
func key(_ text: String, _ code: UInt16, _ modifiers: NSEvent.ModifierFlags = []) {
    let event = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: modifiers, timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: panel.windowNumber, context: nil, characters: text, charactersIgnoringModifiers: text, isARepeat: false, keyCode: code)!
    // NSApplication dispatches command equivalents before the window's keyDown path.
    if !modifiers.contains(.command) || !panel.performKeyEquivalent(with: event) { panel.sendEvent(event) }
    settle()
}

/// Writes the launcher, or a supplied standalone view, to a PNG named for the appearance and size.
/// Standalone views ignore the launcher size, so they are written only at the default size.
func render(_ name: String, view supplied: NSView? = nil) throws {
    if supplied != nil && !defaultScale { return }
    let view = supplied ?? panel.contentView!
    view.layoutSubtreeIfNeeded()
    let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds)!
    view.cacheDisplay(in: view.bounds, to: bitmap)
    try bitmap.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: "/tmp/volant-actions-\(name)\(language.map { "-" + $0 } ?? "")-\(dark ? "dark" : "light")-\(preferences.appearance.scale).png"))
}

/// Sends a native left click at a point in window coordinates, to the launcher unless another window is given.
func click(at point: NSPoint, in target: NSWindow? = nil, downPressure: Float = 0) {
    let window = target ?? panel!
    func mouse(_ type: NSEvent.EventType) -> NSEvent {
        NSEvent.mouseEvent(with: type, location: point, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                          windowNumber: window.windowNumber, context: nil, eventNumber: 1, clickCount: 1, pressure: type == .leftMouseDown ? downPressure : 0)!
    }
    app.postEvent(mouse(.leftMouseUp), atStart: true)
    window.sendEvent(mouse(.leftMouseDown))
    if let release = app.nextEvent(matching: .leftMouseUp, until: .distantPast, inMode: .default, dequeue: true) { window.sendEvent(release) }
    settle()
}

/// Every text field in a view hierarchy.
func fields(_ view: NSView) -> [NSTextField] { (view as? NSTextField).map { [$0] } ?? view.subviews.flatMap(fields) }

/// Restores editing focus to the action or Volant menu search field through its native control,
/// since rendering may end editing.
func focusActionSearch() {
    var field: NSTextField?
    verify(waitUntil { field = fields(panel.contentView!).first { $0.placeholderString == String(localized: "Search for actions…") }; return field != nil },
           "Action search field appears: \(focusState())")
    panel.makeFirstResponder(field!)
    verify(waitUntil(stable: 0.1) { focusedField() === field }, "Action search field takes focus: \(focusState())")
}

/// Finds a control's frame in window coordinates by the identifier of the `ControlAnchor` behind
/// it, or by an AppKit button title, so Settings clicks follow the layout instead of hard-coded
/// points. On a miss it prints what it saw so a layout change is diagnosable from one run.
func controlFrame(_ name: String, in window: NSWindow) -> NSRect? {
    var seen: [String] = []
    func views(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(views) }
    for view in views(window.contentView!) where !view.isHiddenOrHasHiddenAncestor {
        if let identifier = view.identifier?.rawValue, identifier.hasPrefix("settings.") || identifier.hasPrefix("chat.") {
            seen.append(identifier)
            if identifier == name { return view.convert(view.bounds, to: nil) }
        }
        if let button = view as? NSButton, !button.title.isEmpty {
            seen.append(button.title)
            if button.title == name { return button.convert(button.bounds, to: nil) }
        }
    }
    print("Controls seen while looking for \(name): \(seen)")
    return nil
}

/// Shows a standalone SwiftUI view in its own titled window on the semantic window background, lets
/// it lay out, and returns both so the caller can click, render and close it.
func hostWindow<Content: View>(_ content: Content, width: CGFloat, height: CGFloat) -> (NSWindow, NSView) {
    let view = NSHostingView(rootView: content.background(Color(nsColor: .windowBackgroundColor)))
    let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: width, height: height), styleMask: [.titled], backing: .buffered, defer: false)
    window.contentView = view; window.makeKeyAndOrderFront(nil); settle()
    return (window, view)
}

/// Copies the bundled Hello World into a unique fictional folder and rewrites its manifest, so each
/// extension scenario owns its files.
func copyExtension(_ prefix: String, _ edit: (inout ExtensionManifest) -> Void) throws -> (URL, ExtensionManifest) {
    let directory = root.appendingPathComponent(prefix + "-" + UUID().uuidString)
    try FileManager.default.copyItem(at: bundledExtension, to: directory)
    let manifestURL = directory.appendingPathComponent("manifest.json")
    var manifest = try JSONDecoder().decode(ExtensionManifest.self, from: Data(contentsOf: manifestURL))
    edit(&manifest)
    try JSONEncoder().encode(manifest).write(to: manifestURL)
    return (directory, manifest)
}

/// Installs Hello World again as fictional community code with a fictional icon, beside the bundled
/// copy and in the current launcher's configuration, so the master gate, Settings and the catalog see
/// one bundled and one community extension. Community code starts off, as in a new configuration.
func makeCommunityExtension() throws -> (directory: URL, manifest: ExtensionManifest, manager: ExtensionManager) {
    let (directory, manifest) = try copyExtension("community-example") { manifest in
        manifest.id = "fixture.community"; manifest.name = "Community Greeting"
        manifest.icon = "icon.webp"; manifest.iconSha256 = Integrity.sha256(fixtureIcon)
    }
    try fixtureIcon.write(to: directory.appendingPathComponent("icon.webp"))
    let manager = ExtensionManager(configURL: panel.model.actionConfigURL, roots: [bundledExtension, directory])
    manager.reload()
    return (directory, manifest, manager)
}

/// A fictional signed-catalog index: one listing matching the installed community extension and one
/// network extension that is not installed.
func fictionalCatalog(installed: ExtensionManifest) -> ExtensionCatalog {
    ExtensionCatalog(format: 1, sequence: 1, generated: "2026-10-12T00:00:00Z", revision: String(repeating: "0", count: 40), extensions: [
        ExtensionCatalog.Listing(id: installed.id, name: installed.name, version: installed.version, module: installed.module,
                                 summary: "Greets the name you type.", publisher: "Fictional Publisher", license: "MIT", source: "https://example.com/fictional/greeting",
                                 manifest: .init(sha256: String(repeating: "1", count: 64), size: 200),
                                 moduleFile: .init(sha256: installed.sha256!, size: 100),
                                 icon: "icon.webp", iconFile: .init(sha256: Integrity.sha256(fixtureIcon), size: fixtureIcon.count)),
        ExtensionCatalog.Listing(id: "community.fictional.reader", name: "Fictional Reader", version: "1.2.0", module: "reader.wasm",
                                 summary: "Front page and newest stories from a fictional news site.", publisher: "Fictional Publisher", license: "MIT",
                                 hosts: ["news.example.com"], source: "https://example.com/fictional/reader",
                                 manifest: .init(sha256: String(repeating: "2", count: 64), size: 300), moduleFile: .init(sha256: String(repeating: "3", count: 64), size: 4000),
                                 icon: "icon.webp", iconFile: .init(sha256: Integrity.sha256(fixtureIcon), size: fixtureIcon.count)),
    ])
}

/// An empty AI settings file of the scenario's own, so API, ACP and account scenarios never share configuration.
func aiSettingsFile() throws -> URL {
    let url = root.appendingPathComponent("api-settings-\(UUID().uuidString).json")
    try Data("{}".utf8).write(to: url)
    return url
}

/// Action search, keyboard navigation, the empty state, Escape order, copying, Favorites and a native
/// mouse click on a filtered row, whose position follows the launcher size.
func actionsMenuScenario() throws {
    summon()
    key("k", 40, .command)
    verify(waitUntil { panel.model.actionTarget != nil }, "Command K opens actions")
    verify(panel.firstResponder is NSTextView, "Action search receives editing focus")
    try render("menu")
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
    click(at: NSPoint(x: LauncherPanel.size.width - 175, y: 48 + 40 + 9 + min(285, LauncherPanel.size.height - 150) - 18))
    verify(copied == ["Fixture", "Fixture"] && launched == 0, "Native mouse click executes filtered action")
    panel.orderOut(nil)
    print("PASS: native action search, keyboard navigation, empty state, Escape, copying, and Favorites")
}

/// The Volant menu opened by clicking the footer mark: version header, filtering, Return and Escape order.
func volantMenuScenario() throws {
    var menuOpened: [URL] = []
    panel.model.openURL = { menuOpened.append($0) }
    summon()
    // The Volant mark sits at the left of the footer, 10 points above the panel's bottom edge.
    let mark = NSPoint(x: 24, y: 19)
    click(at: mark)
    verify(waitUntil { panel.model.showingAppMenu }, "Clicking the Volant mark opens the Volant menu: \(focusState())")
    verify(panel.model.actionTarget == nil && panel.isVisible, "Volant menu opens inside the panel without item actions")
    verify(LauncherMenuItem.versionTitle() == "Volant v0.0.0", "Version header reads the fixture bundle version, saw \(LauncherMenuItem.versionTitle())")
    focusActionSearch()
    try render("app-menu")
    focusActionSearch()
    (panel.firstResponder as? NSTextView)?.insertText("no such item", replacementRange: NSRange(location: NSNotFound, length: 0)); settle()
    key("\r", 36)
    verify(menuOpened.isEmpty && panel.model.showingAppMenu, "Return on an empty Volant menu filter does nothing")
    focusActionSearch()
    (panel.firstResponder as? NSTextView)?.selectAll(nil)
    (panel.firstResponder as? NSTextView)?.insertText("manual", replacementRange: NSRange(location: NSNotFound, length: 0)); settle()
    verify(panel.model.query.isEmpty, "Volant menu search does not alter launcher query")
    focusActionSearch(); key("\r", 36)
    verify(waitUntil { menuOpened == [LauncherMenuItem.manualURL] } && !panel.model.showingAppMenu, "Return opens the filtered Manual link")
    summon()
    click(at: mark)
    verify(waitUntil { panel.model.showingAppMenu }, "Volant menu opens again")
    focusActionSearch(); key("\u{1b}", 53)
    verify(waitUntil { !panel.model.showingAppMenu } && panel.isVisible, "Escape closes the Volant menu before the launcher")
    verify(waitUntil(stable: 0.1) { focusedField()?.placeholderString == launcherSearchPlaceholder }, "Launcher search regains focus after the menu closes: \(focusState())")
    key("\u{1b}", 53)
    verify(waitUntil { !panel.isVisible }, "A second Escape hides the launcher")
    print("PASS: Volant menu click, version header, filtering, Return, and Escape order")
}

/// AI Chat inside the launcher: setup routing, the native prompt editor, the @ context picker, and an
/// active conversation and draft surviving summon, focus loss and Back. Entering AI Chat invokes setup
/// routing, never a real provider. AI Settings is drawn last because it shows this live conversation.
func panelChatScenario() throws {
    summon(); key("\t", 48)
    verify(waitUntil { settingsRequests == 1 && !panel.isVisible }, "Unconfigured AI Chat routes to Settings")
    chatConfig = AIConfiguration(); chatConfig?.provider = "claude"
    summon()
    (panel.firstResponder as? NSTextView)?.insertText("A fictional question", replacementRange: NSRange(location: NSNotFound, length: 0)); settle()
    key("\t", 48)
    verify(waitUntil { panel.model.acp.draft == "A fictional question" } && !panel.model.acp.submitting, "Tab carries search text to an unsent chat draft")
    panel.model.acp.draft = ""; settle()
    verify(panel.model.acp.state.phase == "ready" && panel.model.acp.project.isEmpty, "Configured AI Chat automatically connects without a project")
    awaitChatPrompt("Chat prompt receives focus")
    (panel.firstResponder as? NSTextView)?.insertText("A fictional question", replacementRange: NSRange(location: NSNotFound, length: 0)); settle()
    if panel.model.acp.draft != "A fictional question" || panel.model.query != "ai" {
        try render("chat-focus-failure")
        print("Chat focus diagnostic: draft length \(panel.model.acp.draft.count), query length \(panel.model.query.count), presented \(panel.model.showingACP)")
    }
    verify(panel.model.acp.draft == "A fictional question" && panel.model.query == "ai", "Typing edits the chat prompt instead of launcher search")
    key("\r", 36, .shift)
    verify(panel.model.acp.draft.contains("\n") && !panel.model.acp.submitting, "Shift Return inserts a newline without sending")
    let draftBeforeUndo = panel.model.acp.draft
    (panel.firstResponder as? NSTextView)?.undoManager?.undo(); settle()
    // AppKit may coalesce adjacent typing into one undo group; the binding must follow the actual editor.
    verify(panel.model.acp.draft != draftBeforeUndo && panel.model.acp.draft == (panel.firstResponder as? NSTextView)?.string, "Undo updates the chat draft binding")
    panel.model.acp.draft = "A fictional question"; settle()
    key("\r", 36)
    verify(panel.model.acp.submitting, "Return submits through the native chat editor")
    // The fixture has no XPC connection; reset the local submitting flag without sending a real prompt.
    panel.model.acp.submitting = false
    panel.model.acp.draft = ""; settle()
    key("\r", 36)
    verify(!panel.model.acp.submitting, "Return does not submit an empty draft")
    panel.model.acp.draft = "A fictional question"; settle()
    if let editor = panel.firstResponder as? NSTextView {
        editor.setMarkedText("かな", selectedRange: NSRange(location: 2, length: 0), replacementRange: NSRange(location: NSNotFound, length: 0))
        verify(editor.hasMarkedText(), "Fixture begins input method composition")
        key("\r", 36)
        verify(!panel.model.acp.submitting, "Return during marked text composition does not submit")
        editor.unmarkText()
    }
    panel.model.acp.draft = "A fictional follow-up"; settle()
    panel.model.acp.state.messages = [
        ACPMessage(role: "You", text: "Show me a **literal** Markdown example."),
        ACPMessage(role: "Agent", text: "## A clearer answer\nUse **bold** for emphasis and `code` for names.\n\n- Keep messages readable\n- Copy code when needed\n\n```swift\nlet greeting = \"Hello, world!\"\nprint(greeting)")
    ]
    settle()
    try render("chat-streaming")
    panel.model.acp.state.messages[1].text += "\n```\n\nSee [the example](https://example.com)."
    settle()
    verify(panel.model.acp.draft == "A fictional follow-up", "Streaming Markdown preserves the prompt draft")
    try render("chat")
    // The @ picker is driven by real keystrokes against a fictional clipboard entry.
    clipboard.record("Fictional build error: expected ';' after expression"); settle()
    if let editor = panel.firstResponder as? NSTextView { editor.setSelectedRange(NSRange(location: (editor.string as NSString).length, length: 0)) }
    key(" ", 49); key("@", 19, [.shift]); settle()
    verify(controlFrame("chat.picker", in: panel) != nil, "Typing @ at the start of a word opens the picker")
    try render("chat-context-picker")
    key("\r", 36)
    verify(panel.model.acp.attachments.count == 1 && panel.model.acp.attachments.first?.kind == .clipboard, "Return attaches the first candidate")
    verify(!panel.model.acp.draft.contains("@"), "Choosing removes the @ that opened the picker")
    verify(controlFrame("chat.picker", in: panel) == nil, "The picker closes after choosing")
    verify(!panel.model.acp.submitting, "Choosing an attachment never sends")
    panel.model.acp.state.messages.append(ACPMessage(role: "You", text: "Why does this fail?", attachments: ["Fictional build error: expected ';' after expression"]))
    settle()
    try render("chat-attached")
    panel.model.acp.detach(panel.model.acp.attachments[0].id)
    panel.model.acp.state.messages.removeLast()
    panel.model.acp.draft = "A fictional follow-up"; settle()
    print("PASS: @ opens the context picker at a word start, Return attaches a snapshot and removes the @, without sending")
    let savedMessages = panel.model.acp.state.messages
    let savedDraft = panel.model.acp.draft
    panel.orderOut(nil); settle(); summon()
    verify(!panel.model.showingACP && panel.model.query.isEmpty, "Summoning a hidden chat opens the default launcher")
    verify(panel.model.acp.state.messages == savedMessages && panel.model.acp.draft == savedDraft && panel.model.acp.active, "Summoning preserves the active conversation and draft")
    try render("chat-home")
    panel.model.config.statusBar.sources = ["ai-chat"]
    settle()
    try render("chat-status-pinned")
    panel.model.config.statusBar.sources = []
    settle()
    let search = fields(panel.contentView!).first { $0.placeholderString == launcherSearchPlaceholder }!
    panel.makeFirstResponder(search)
    verify(waitUntil(stable: 0.1) { focusedField() === search }, "Launcher search takes focus before typing: \(focusState())")
    (panel.firstResponder as? NSTextView)?.insertText("Do not replace my draft", replacementRange: NSRange(location: NSNotFound, length: 0)); settle()
    key("\t", 48)
    awaitChatPrompt("Tab resumes chat")
    verify(panel.model.acp.draft == savedDraft, "Tab resumes chat without overwriting its draft")
    // A busy chat stays visible on blur, but a subsequent summon returns to search.
    panel.model.acp.state.phase = "working"
    let backgroundWindow = NSWindow(contentRect: NSRect(x: 20, y: 20, width: 180, height: 100), styleMask: [.titled], backing: .buffered, defer: false)
    backgroundWindow.makeKeyAndOrderFront(nil); settle()
    verify(panel.isVisible && !panel.isKeyWindow && panel.model.showingACP, "Working chat remains visible on real focus loss")
    summon()
    verify(!panel.model.showingACP && panel.model.query.isEmpty && panel.model.acp.state.phase == "working", "Summoning a visible inactive chat returns home without stopping the turn")
    verify(panel.model.acp.state.messages == savedMessages && panel.model.acp.draft == savedDraft, "Focus loss and summon preserve conversation state")
    key("\t", 48)
    awaitChatPrompt("Tab resumes the working conversation")
    backgroundWindow.orderOut(nil)
    panel.model.acp.state.phase = "ready"
    (panel.firstResponder as? NSTextView)?.insertText("!", replacementRange: NSRange(location: NSNotFound, length: 0)); settle()
    verify(panel.model.acp.draft.contains("!") && panel.model.query == "ai", "Resuming chat restores native prompt focus")
    click(at: NSPoint(x: 20, y: LauncherPanel.size.height - 18))
    verify(!panel.model.showingACP && panel.model.acp.active && !panel.model.acp.draft.isEmpty, "Back returns to search without ending chat or discarding its draft")
    try render("chat-back")
    panel.orderOut(nil)
    let settings = SettingsWindowController(configURL: panel.model.actionConfigURL, conversations: panel.model.conversations) {}
    try chatConfig!.save(at: panel.model.actionConfigURL)
    settings.state.section = .ai
    settings.window!.setContentSize(NSSize(width: 680, height: 500))
    settings.showWindow(nil); settle()
    try render("ai-settings-active", view: settings.window!.contentView!)
    panel.model.acp.state.phase = "disconnected"
    settle()
    try render("ai-settings", view: settings.window!.contentView!)
    settings.window!.orderOut(nil)
    print("PASS: AI Chat setup routing, automatic general-chat connection, prompt focus, and active-draft preservation")
}

/// Bundled extensions start off: everyday search leaves them out, `ext` finds them, and nothing runs
/// before consent. The master gate applies to installed community code, never a manifest's claimed
/// origin or ID, and a consent granted before the gate closed cannot run it.
func communityLauncherScenario() throws {
    panel.toggle()
    panel.model.query = "hello Andrew"
    settle()
    verify(!panel.model.rows.contains { if case .extensionRun = $0 { return true }; return false }, "Hello World starts off and out of everyday search")
    panel.model.query = "ext hello Andrew"; settle()
    verify(panel.model.rows.first?.primaryAction == "Enable and Run…", "ext lists Hello World, which starts disabled")
    verify(!panel.model.extensionRunning && panel.model.pendingExtension == nil, "Typing an extension name never executes or enables it")
    try render("direct-extension-launcher")

    key("\r", 36)
    verify(panel.model.pendingExtension?.input == "Andrew", "First invocation requests consent without executing")
    verify(panel.keepsVisibleOnBlur, "Extension consent keeps its parent panel visible")
    let permission = panel.model.pendingExtension!
    let consentView = NSHostingView(rootView: ExtensionPermissionView(request: permission, enable: { _ in }, cancel: {}))
    consentView.frame = NSRect(x: 0, y: 0, width: 438, height: 240)
    try render("extension-consent", view: consentView)
    panel.model.pendingExtension = nil
    settle()
    panel.orderOut(nil)

    let community = try makeCommunityExtension()
    let communityManager = community.manager
    var communityManifest = community.manifest
    let communityManifestURL = community.directory.appendingPathComponent("manifest.json")
    verify(!communityManager.communityAllowed, "Community extensions default off")
    verify(!communityManager.extensions.first(where: { !$0.isCommunity })!.communityBlocked, "Bundled example is independent of master gate")
    panel.model.extensions = communityManager
    communityManifest.name = "Fixture"
    try JSONEncoder().encode(communityManifest).write(to: communityManifestURL)
    communityManager.reload()
    panel.model.query = "Fixture"; settle()
    verify(panel.model.rows.contains { if case .app = $0 { return true }; return false }, "An extension name cannot hide a matching application")
    verify(communityManager.loadErrors.isEmpty, "Copied community extension loads: \(communityManager.loadErrors)")
    verify(!panel.model.rows.contains { if case .extensionRun = $0 { return true }; return false }, "An extension that is off stays out of everyday search")
    communityManifest.name = "Community Greeting"
    try JSONEncoder().encode(communityManifest).write(to: communityManifestURL)
    communityManager.reload()

    panel.model.query = "community"; settle()
    verify(!panel.model.rows.contains { if case .extensionRun = $0 { return true }; return false }, "Master-blocked commands stay out of everyday search")
    panel.model.query = "ext community"; settle()
    verify(panel.model.rows.contains { if case .extensionRun = $0 { return true }; return false }, "ext lists master-blocked commands without execution")

    panel.toggle(); panel.model.query = "ext community Andrew"; settle()
    verify(panel.model.rows.first?.primaryAction == "Open Extension Settings", "Blocked community command points to Settings")
    try render("community-blocked-launcher")
    key("\r", 36)
    verify(extensionSettingsRequests == 1 && panel.model.pendingExtension == nil, "Master off routes to Settings without offering enable or executing")
    try communityManager.setCommunityAllowed(true, expected: false)
    panel.toggle(); panel.model.query = "ext community Andrew"; settle()
    verify(panel.model.rows.first?.primaryAction == "Enable and Run…", "Allowing community code still requires individual consent")
    try render("community-first-use-launcher")
    key("\r", 36)
    verify(panel.model.pendingExtension?.extensionItem.id == "fixture.community", "Community first use requests per-extension consent")
    try communityManager.setCommunityAllowed(false, expected: true)
    panel.model.enablePendingExtension()
    verify(!panel.model.extensionRunning && !ExtensionApproval.enabled(communityManifest, at: panel.model.actionConfigURL), "Stale consent cannot bypass revoked master gate")
    panel.orderOut(nil)
    print("PASS: community master default, Settings routing, individual consent and stale consent rejection")
}

/// Extension Settings with the community master gate off, on with the extension enabled, beside the
/// fictional catalog, and paused again; the window's Extensions section shows the bundled example.
func communitySettingsScenario() throws {
    let settings = SettingsWindowController(configURL: panel.model.actionConfigURL, conversations: panel.model.conversations) {}
    settings.state.section = .extensions
    settings.window!.setContentSize(NSSize(width: 680, height: 500))
    settings.showWindow(nil); settle()
    try render("extension-settings", view: settings.window!.contentView!)
    settings.window!.orderOut(nil)

    let (communityDirectory, _, communityManager) = try makeCommunityExtension()
    func renderCommunitySettings(_ name: String, catalog: ExtensionCatalog? = nil, height: CGFloat = 440) throws {
        let (window, view) = hostWindow(ExtensionSettingsView(configURL: panel.model.actionConfigURL, onChange: {}, roots: [bundledExtension, communityDirectory],
                                                              catalogClient: ExtensionCatalogClient(fetchFile: { _, _, _ in }), catalog: catalog),
                                        width: 460, height: height)
        view.layoutSubtreeIfNeeded(); settle()
        try render(name, view: view)
        window.orderOut(nil)
    }
    try renderCommunitySettings("community-off")
    try communityManager.setCommunityAllowed(true, expected: false)
    try communityManager.setEnabled(communityManager.search("community").first!, true)
    try renderCommunitySettings("community-on")
    verify(ExtensionIcon.image(for: communityManager.search("community").first!) != nil, "A valid extension icon loads for rows")
    let catalog = fictionalCatalog(installed: communityManager.search("community").first!.manifest)
    verify(ExtensionManager.catalogStatus(catalog.extensions[0], installed: communityManager.extensions) == .installed, "Matching catalog listing reads as installed")
    try renderCommunitySettings("community-catalog", catalog: catalog, height: 760)
    var newer = catalog
    newer.extensions[0].version = "1.1.0"; newer.extensions[0].moduleFile.sha256 = String(repeating: "4", count: 64)
    verify(ExtensionManager.catalogStatus(newer.extensions[0], installed: communityManager.extensions) == .update(from: catalog.extensions[0].version),
           "A newer catalog version offers an update on the Extensions page")
    try renderCommunitySettings("community-updates", catalog: newer, height: 760)
    let (browseWindow, browseView) = hostWindow(ExtensionBrowseView(catalog: newer, loading: false, error: nil, installing: nil, installed: communityManager.extensions,
                                                                    communityAllowed: true, load: {}, install: { _ in }, done: {}),
                                                width: 620, height: 520)
    browseView.layoutSubtreeIfNeeded(); settle()
    try render("community-browse", view: browseView)
    browseWindow.orderOut(nil)
    try? FileManager.default.removeItem(at: communityManager.catalogStateURL)
    var revoking = catalog
    revoking.sequence = 2
    revoking.revoked = [.init(id: catalog.extensions[0].id, sha256: catalog.extensions[0].moduleFile.sha256, reason: "Fictional reason for withdrawing it.")]
    verify(communityManager.applyRevocations(from: revoking).map(\.id) == [catalog.extensions[0].id], "A revocation turns off the installed copy")
    try renderCommunitySettings("community-revoked", catalog: revoking, height: 760)
    try FileManager.default.removeItem(at: communityManager.catalogStateURL)
    communityManager.reload()
    try communityManager.setCommunityAllowed(false, expected: true)
    try renderCommunitySettings("community-paused")
    try renderCommunitySettings("community-catalog-paused", catalog: catalog, height: 760)
    print("PASS: community extension Settings render off, on, up to date, with an update, browsing, revoked, and paused")
}

/// A list extension with storage: its rows offer actions in Actions and Pin saves data; then a
/// weather-style list extension names a row symbol per condition, which Volant draws in color in
/// place of the extension's icon, with an unknown name falling back to that icon.
func extensionRowsScenario() throws {
    let (storageDirectory, _) = try copyExtension("storage-reader") { manifest in
        manifest.id = "fixture.reader"; manifest.name = "Fixture Reader"; manifest.output = "items"; manifest.storage = true
    }
    let storageManager = ExtensionManager(configURL: panel.model.actionConfigURL, roots: [storageDirectory], dataDirectory: root.appendingPathComponent("ExtensionData-" + UUID().uuidString))
    storageManager.reload()
    try storageManager.setCommunityAllowed(true, expected: false)
    try storageManager.setEnabled(storageManager.extensions.first!, true)
    var storageRequests: [String] = []
    storageManager.invokeOverride = { _, input, completion in
        storageRequests.append(input)
        if input.contains(#""phase":"action""#) {
            completion(.success(#"{"storage":{"pinned":["1"]}}"#))
        } else if input.contains(#""pinned":["1"]"#) {
            completion(.success(#"{"items":[{"title":"Fictional story","subtitle":"Pinned · fixture.example.com","url":"https://fixture.example.com/1"}]}"#))
        } else {
            completion(.success(#"{"items":[{"title":"Fictional story","subtitle":"fixture.example.com","url":"https://fixture.example.com/1","actions":[{"id":"pin","title":"Pin Story"},{"id":"hide","title":"Hide Story"}]}]}"#))
        }
    }
    panel.model.extensions = storageManager
    panel.toggle(); panel.model.query = "Fixture Reader"; settle()
    key("\r", 36)
    verify(waitUntil { panel.model.rows.first.map { if case .extensionItem = $0 { return true }; return false } == true }, "A storage list extension shows its rows")
    verify(storageRequests.first?.contains(#""storage":{}"#) == true, "The first run receives an empty saved object")
    key("k", 40, .command); settle()
    verify(panel.model.actionTarget != nil, "Command K opens a row's Actions")
    try render("extension-row-actions")
    verify(panel.model.actionTarget?.menuEntries == [.item(.open), .item(.copyPath), .custom(ExtensionItemAction(id: "pin", title: "Pin Story")),
                                                      .custom(ExtensionItemAction(id: "hide", title: "Hide Story"))],
           "A linked row offers Open Link and Copy Link before its own actions")
    key("\u{F701}", 125); key("\u{F701}", 125); key("\r", 36); settle()
    verify(storageManager.storedData(storageManager.extensions.first!) == .object(["pinned": .array([.string("1")])]), "Pin saves the extension's data")
    verify(storageRequests.count == 3 && storageRequests[1].contains(#""action":"pin""#) && storageRequests[2].contains(#""phase":"render""#),
           "A storage-only action reply runs the list again")
    verify(panel.model.rows.first.map { if case .extensionItem(let item, _) = $0 { return item.subtitle?.hasPrefix("Pinned") == true }; return false } == true,
           "The list run after Pin shows the pinned story")
    panel.orderOut(nil)

    let (symbolDirectory, _) = try copyExtension("symbol-weather") { manifest in
        manifest.id = "fixture.weather"; manifest.name = "Fixture Weather"; manifest.output = "items"
    }
    let symbolManager = ExtensionManager(configURL: panel.model.actionConfigURL, roots: [symbolDirectory], dataDirectory: root.appendingPathComponent("SymbolData-" + UUID().uuidString))
    symbolManager.reload()
    try symbolManager.setCommunityAllowed(true, expected: symbolManager.communityAllowed)
    try symbolManager.setEnabled(symbolManager.extensions.first!, true)
    symbolManager.invokeOverride = { _, _, completion in
        completion(.success(#"{"items":[{"title":"Now · 24°","subtitle":"Sunny in Fictionville","url":"https://weather.example.com/now","symbol":"sun"},{"title":"Tonight · 15°","subtitle":"Partly cloudy","url":"https://weather.example.com/tonight","symbol":"cloud-moon"},{"title":"Tomorrow · 18°","subtitle":"Rain","url":"https://weather.example.com/tomorrow","symbol":"rain"},{"title":"Friday · 2°","subtitle":"Snow","url":"https://weather.example.com/friday","symbol":"snow"},{"title":"Saturday · 21°","subtitle":"Thunderstorms","url":"https://weather.example.com/saturday","symbol":"thunderstorm"},{"title":"Sunday · 19°","subtitle":"Unknown symbol","url":"https://weather.example.com/sunday","symbol":"tornado"}]}"#))
    }
    panel.model.extensions = symbolManager
    panel.toggle(); panel.model.query = "Fixture Weather"; settle()
    key("\r", 36); settle()
    let symbolRows = panel.model.rows.compactMap { row -> ExtensionItem? in if case .extensionItem(let item, _) = row { return item }; return nil }
    verify(symbolRows.map(\.symbol) == ["sun", "cloud-moon", "rain", "snow", "thunderstorm", nil], "Rows keep known symbols and drop unknown ones")
    try render("extension-row-symbols")
    panel.orderOut(nil)
    try storageManager.setCommunityAllowed(false, expected: true)
    print("PASS: storage list extension receives and saves data, and row actions run from Actions")
}

/// Dictation Settings with a fictional vocabulary, and the sheet that adds a word. Output stays on
/// Copy, so the input helper is never started.
func dictationVocabularyScenario() throws {
    let vocabulary = [DictationVocabularyEntry(term: "Kubernetes", soundsLike: ["Kubernitz", "cooper netties"]),
                      DictationVocabularyEntry(term: "PostgreSQL", soundsLike: ["post-Ger SQL"]),
                      DictationVocabularyEntry(term: "Tailscale", soundsLike: ["tail scale"]),
                      DictationVocabularyEntry(term: "Sparkle")]
    try Preferences.updateDictationVocabulary(vocabulary, expected: [], at: panel.model.actionConfigURL)
    let settings = SettingsWindowController(configURL: panel.model.actionConfigURL, conversations: panel.model.conversations) {}
    settings.refresh(try JSONDecoder().decode(Preferences.self, from: Data(contentsOf: panel.model.actionConfigURL)))
    verify(settings.state.config.dictationVocabulary == vocabulary && settings.state.config.dictationOutput == .copy, "Dictation Settings reads the saved vocabulary")
    settings.state.section = .dictation
    settings.window!.setContentSize(NSSize(width: 680, height: 760))
    settings.showWindow(nil); settle()
    try render("dictation-vocabulary-settings", view: settings.window!.contentView!)
    settings.window!.orderOut(nil)
    let (editorWindow, editorView) = hostWindow(VocabularyEntryEditor(edit: VocabularyEdit(original: vocabulary[0]), cancel: {}, save: { _ in }),
                                                width: 400, height: 300)
    editorView.layoutSubtreeIfNeeded(); settle()
    try render("dictation-vocabulary-editor", view: editorView)
    editorWindow.orderOut(nil)
    print("PASS: Dictation Settings lists the vocabulary with its mishearings, and the word editor renders")
}

/// Extension Settings offers Clear Data for a storage extension's saved data, and an extension with a
/// saved token, saved data, a location grant and community origin shows all three row buttons at
/// Settings' 680-point minimum width without squeezing its subtitle; its location prompt is drawn first.
func extensionSettingsScenario() throws {
    let storageData = root.appendingPathComponent("ExtensionData-" + UUID().uuidString)
    let (storageDirectory, _) = try copyExtension("storage-reader") { manifest in
        manifest.id = "fixture.reader"; manifest.name = "Fixture Reader"; manifest.output = "items"; manifest.storage = true
    }
    let storageManager = ExtensionManager(configURL: panel.model.actionConfigURL, roots: [storageDirectory], dataDirectory: storageData)
    storageManager.reload()
    try storageManager.setCommunityAllowed(true, expected: false)
    try storageManager.setEnabled(storageManager.extensions.first!, true)
    try storageManager.dataStore.save(.object(["pinned": .array([.string("1")])]), for: "fixture.reader")
    verify(storageManager.hasStoredData(storageManager.extensions.first!), "The storage fixture has saved data")
    let (storageWindow, storageView) = hostWindow(ExtensionSettingsView(configURL: panel.model.actionConfigURL, onChange: {}, roots: [storageDirectory],
                                                                        dataDirectory: storageData, catalogClient: ExtensionCatalogClient(fetchFile: { _, _, _ in })),
                                                  width: 460, height: 440)
    storageView.layoutSubtreeIfNeeded(); settle()
    try render("extension-storage-settings", view: storageView)
    storageWindow.orderOut(nil)

    let (preferenceDirectory, _) = try copyExtension("preference-reader") { manifest in
        manifest.id = "fixture.preferences"; manifest.name = "Fixture Headlines"; manifest.output = "items"
        manifest.preferences = [
            ExtensionPreference(id: "sort", type: .dropdown, title: "Sort stories by",
                                choices: [ExtensionFilter(id: "top", title: "Top"), ExtensionFilter(id: "new", title: "Newest")]),
            ExtensionPreference(id: "hideDomains", type: .text, title: "Hidden domains", description: "Comma-separated, such as fictional.example",
                                placeholder: "fictional.example", maxLength: 200),
            ExtensionPreference(id: "limit", type: .number, title: "Stories to show", defaultValue: .number(30), min: 5, max: 50),
            ExtensionPreference(id: "showScores", type: .toggle, title: "Show scores", description: "Adds each story's points to its row",
                                defaultValue: .bool(true)),
        ]
    }
    let preferenceManager = ExtensionManager(configURL: panel.model.actionConfigURL, roots: [preferenceDirectory], dataDirectory: storageData)
    preferenceManager.reload()
    let preferenceExtension = preferenceManager.extensions.first!
    try preferenceManager.setEnabled(preferenceExtension, true)
    try preferenceManager.savePreferences(["hideDomains": .string("fictional.example"), "limit": .number(20)], for: preferenceExtension, expected: [:])
    let (preferenceWindow, preferenceSettings) = hostWindow(ExtensionSettingsView(configURL: panel.model.actionConfigURL, onChange: {},
                                                                                  roots: [preferenceDirectory], dataDirectory: storageData,
                                                                                  catalogClient: ExtensionCatalogClient(fetchFile: { _, _, _ in })),
                                                            width: 460, height: 440)
    preferenceSettings.layoutSubtreeIfNeeded(); settle()
    try render("extension-preference-settings", view: preferenceSettings)
    preferenceWindow.orderOut(nil)
    let preferenceSheet = NSHostingView(rootView: ExtensionPreferencesView(ext: preferenceManager.extensions.first!, manager: preferenceManager, done: {}))
    preferenceSheet.frame = NSRect(x: 0, y: 0, width: 460, height: 440); preferenceSheet.layoutSubtreeIfNeeded(); settle()
    try render("extension-preferences-sheet", view: preferenceSheet)

    let (hackerNewsDirectory, _) = try copyExtension("hacker-news-preferences") { manifest in
        manifest.id = "community.volant.hn"; manifest.name = "Hacker News"; manifest.output = "items"
        manifest.preferences = [
            ExtensionPreference(id: "limit", type: .number, title: "Stories to show", description: "How many stories to load at once",
                                defaultValue: .number(30), min: 10, max: 50),
            ExtensionPreference(id: "minimumPoints", type: .number, title: "Minimum points", description: "Hide stories with fewer points; 0 shows all",
                                defaultValue: .number(0), min: 0, max: 1000),
            ExtensionPreference(id: "showBadges", type: .toggle, title: "Show points and comments",
                                description: "Adds each story's points, comment count and site to its row", defaultValue: .bool(true)),
        ]
    }
    let hackerNewsManager = ExtensionManager(configURL: panel.model.actionConfigURL, roots: [hackerNewsDirectory], dataDirectory: storageData)
    hackerNewsManager.reload()
    try hackerNewsManager.setEnabled(hackerNewsManager.extensions.first!, true)
    try hackerNewsManager.savePreferences(["limit": .number(40), "minimumPoints": .number(50)], for: hackerNewsManager.extensions.first!, expected: [:])
    let hackerNewsSheet = NSHostingView(rootView: ExtensionPreferencesView(ext: hackerNewsManager.extensions.first!, manager: hackerNewsManager, done: {}))
    hackerNewsSheet.frame = NSRect(x: 0, y: 0, width: 460, height: 400); hackerNewsSheet.layoutSubtreeIfNeeded(); settle()
    try render("hacker-news-preferences-sheet", view: hackerNewsSheet)
    verify(preferenceManager.preferenceValues(preferenceManager.extensions.first!)["hideDomains"] == .string("fictional.example"),
           "Saved preferences are what the sheet and the next run read")

    let (tokenDirectory, tokenManifest) = try copyExtension("token-tasks") { manifest in
        manifest.id = "fixture.tasks"; manifest.name = "Fixture Tasks"; manifest.output = "items"; manifest.storage = true
        manifest.hosts = ["api.tasks.example.com"]; manifest.permissions = ["location"]
        manifest.secrets = [ExtensionSecret(id: "token", title: "Fictional API token", host: "api.tasks.example.com", header: "Authorization", prefix: "Bearer ")]
    }
    let tokenSecrets = ExtensionSecretStore.memory()
    let tokenManager = ExtensionManager(configURL: panel.model.actionConfigURL, roots: [tokenDirectory], dataDirectory: storageData)
    tokenManager.secretStore = tokenSecrets; tokenManager.reload()
    try tokenManager.setEnabled(tokenManager.extensions.first!, true)
    try tokenManager.saveSecrets(tokenManager.extensions.first!, ["token": "fictional-token-123"])
    try tokenManager.dataStore.save(.object(["seen": .array([.string("1")])]), for: "fixture.tasks")
    let locationPrompt = NSHostingView(rootView: ExtensionPermissionView(
        request: ExtensionPermissionRequest(extensionItem: tokenManager.extensions.first!, input: "", hosts: ["api.tasks.example.com"],
                                            secrets: tokenManifest.secrets ?? [], location: true), enable: { _ in }, cancel: {}))
    locationPrompt.frame = NSRect(x: 0, y: 0, width: 390, height: 520); locationPrompt.layoutSubtreeIfNeeded(); settle()
    try render("extension-location-prompt", view: locationPrompt)
    try tokenManager.allowLocation(tokenManager.extensions.first!)
    verify(tokenManager.hasSecrets(tokenManager.extensions.first!) && tokenManager.hasStoredData(tokenManager.extensions.first!),
           "The token fixture has a saved token and saved data")
    let (tokenWindow, tokenSettings) = hostWindow(ExtensionSettingsView(configURL: panel.model.actionConfigURL, onChange: {}, roots: [tokenDirectory],
                                                                        dataDirectory: storageData, catalogClient: ExtensionCatalogClient(fetchFile: { _, _, _ in }),
                                                                        secretStore: tokenSecrets),
                                                  width: 680, height: 1100)
    tokenSettings.layoutSubtreeIfNeeded(); settle()
    try render("extension-token-settings", view: tokenSettings)
    tokenWindow.orderOut(nil)
    try storageManager.setCommunityAllowed(false, expected: true)
    print("PASS: extension Settings show Clear Data, a saved token and a location grant")
}

/// The launcher's Extension Catalog: typing never fetches; Check Catalog loads a signed fictional
/// index whose first listing matches the enabled community extension.
func catalogScenario() throws {
    let (_, _, communityManager) = try makeCommunityExtension()
    try communityManager.setCommunityAllowed(true, expected: false)
    try communityManager.setEnabled(communityManager.search("community").first!, true)
    panel.model.extensions = communityManager
    let fixtureCatalogKey = Curve25519.Signing.PrivateKey()
    let fixtureIndex = try JSONEncoder().encode(fictionalCatalog(installed: communityManager.search("community").first!.manifest))
    var fixtureCatalogFetches = 0, fixtureIconFetches = 0
    panel.model.catalog.client = ExtensionCatalogClient(fetchFile: { path, _, completion in
        switch path {
        case ExtensionCatalog.indexPath: fixtureCatalogFetches += 1; completion(.success(fixtureIndex))
        case ExtensionCatalog.signaturePath:
            fixtureCatalogFetches += 1; completion(.success(Data(try! fixtureCatalogKey.signature(for: fixtureIndex).base64EncodedString().utf8)))
        case _ where path.hasSuffix("/icon.webp"): fixtureIconFetches += 1; completion(.success(fixtureIcon))
        default: completion(.failure(ExtensionCatalogError.unavailable("Fixture has no packages.")))
        }
    }, publicKey: fixtureCatalogKey.publicKey.rawRepresentation.base64EncodedString(), stateURL: root.appendingPathComponent("extension-catalog-\(UUID().uuidString).json"))
    panel.toggle(); panel.model.query = "catalog"; settle()
    verify(panel.model.showingCatalog && fixtureCatalogFetches == 0 && fixtureIconFetches == 0, "Typing catalog opens the catalog view without fetching")
    try render("catalog-check-launcher")
    func catalogField(in view: NSView) -> NSTextField? {
        if let field = view as? NSTextField, field.placeholderString == "Search extensions…" { return field }
        return view.subviews.lazy.compactMap { catalogField(in: $0) }.first
    }
    verify(panel.makeFirstResponder(catalogField(in: panel.contentView!)!), "Focus the catalog search field")
    key("\r", 36)
    verify(waitUntil { fixtureCatalogFetches == 2 && panel.model.catalog.listings.count == 2 }, "Return checks the signed catalog once")
    let notInstalled = panel.model.catalog.listings.first { $0.id == "community.fictional.reader" }!
    verify(waitUntil { ExtensionCatalogIcons.shared.image(for: notInstalled) != nil }, "A listing that isn't installed shows its verified catalog icon")
    verify(panel.model.catalog.primaryTitle == "Use Extension", "An installed listing offers to use it")
    try render("catalog-launcher")
    key("\u{F701}", 125); settle()
    verify(panel.model.catalog.selected?.id == "community.fictional.reader" && panel.model.catalog.primaryTitle == "Install", "Down arrow selects the next listing")
    try render("catalog-detail-launcher")
    panel.model.catalog.input = "news.example"; settle()
    verify(panel.model.catalog.listings.count == 1, "Typing filters the loaded catalog, including by host")
    try render("catalog-filtered-launcher")
    panel.orderOut(nil)
    panel.model.extensionUpdates = { [.init(name: "Fictional Reader", version: "1.2.0"), .init(name: "Community Greeting", version: "1.1.0")] }
    panel.toggle(); panel.model.query = ""; settle()
    verify(panel.model.rows.first.map { if case .extensionUpdates = $0 { return true }; return false } == true, "Extension updates lead the suggestions")
    try render("extension-updates-launcher")
    panel.orderOut(nil)
    panel.model.extensionUpdates = { [] }
    try communityManager.setCommunityAllowed(false, expected: true)
    print("PASS: launcher catalog checks only on request, filters locally and labels install state")
}

/// Herdr in the launcher: local panes stay usable while a remote machine loads, passive question
/// previews use fictional terminal output and no helper connection, answers are clicked at fixed card
/// positions, equal pane IDs stay separate by machine, and the footer counts and names machines.
func herdrScenario() throws {
    panel.model.agents.connected = true
    panel.model.agents.busy = true
    panel.model.agents.sessions = [AgentSession(agent: "codex", agentStatus: "working", paneID: "w1:p1", terminalID: "local-fixture", cwd: "/fictional/local-project", terminalTitle: nil, agentSession: nil)]
    panel.model.agents.machines = [
        .init(id: "local", label: "Local", state: "connected", detail: "1 pane"),
        .init(id: "remote:fixture", label: "Build Mac", state: "loading", detail: "Loading panes…")
    ]
    panel.toggle()
    panel.model.query = "agents"
    verify(waitUntil { panel.model.showingAgents && panel.model.rows.count == 1 }, "Local pane is usable while the remote machine loads")
    try render("machines-loading")
    panel.orderOut(nil)
    panel.model.query = ""
    panel.model.agents.busy = false

    panel.model.agents.connected = true
    panel.model.promotedHarness = "all"
    var waitingClaude = AgentSession(agent: "claude", agentStatus: "blocked", paneID: "w1:p1", terminalID: "question-one", cwd: "/fictional/orbit", terminalTitle: nil, agentSession: .init(value: "claude-fictional"))
    let waitingCodex = AgentSession(agent: "codex", agentStatus: "blocked", paneID: "w1:p2", terminalID: "question-two", cwd: "/fictional/comet", terminalTitle: nil, agentSession: .init(value: "codex-fictional"))
    waitingClaude.machine = HerdrMachine(id: "fixture-remote", label: "Build Mac", target: "fictional-host", session: "agents", enabled: true)
    panel.model.agents.machines = [
        .init(id: "local", label: "Local", state: "connected", detail: "1 pane"),
        .init(id: "fixture-remote", label: "Build Mac", state: "connected", detail: "1 pane"),
        .init(id: "fixture-offline", label: "Lab", state: "unavailable", detail: "Check SSH access and Herdr 0.9.1 or later on this machine.")
    ]
    var previewReply: ((Data?, String?) -> Void)?
    panel.model.agents.attentionReader = { _, reply in previewReply = reply }
    panel.model.agents.sessions = [waitingClaude, waitingCodex]
    panel.toggle()
    // The footer shows the waiting count; the question itself lives in the herdr view.
    verify(panel.model.promotedHarness == "all", "Herdr status is enabled for the footer")
    panel.model.showPromotedAgents()
    verify(panel.model.query == "herdr" && panel.model.showingAgents, "Footer status opens the herdr view")
    // SwiftUI starts the preview in .task after presentation. A fixed 200 ms delay
    // can expire on a loaded CI runner before that task starts; wait for its effect.
    let previewDeadline = Date().addingTimeInterval(3)
    while (!panel.model.agents.attentionLoading || previewReply == nil) && Date() < previewDeadline {
        RunLoop.main.run(until: Date().addingTimeInterval(0.02))
    }
    verify(panel.model.agents.attentionLoading && previewReply != nil, "Waiting agent in the herdr view starts a passive preview read")
    try render("attention-loading")
    previewReply?(try JSONEncoder().encode(HerdrResponseController.Snapshot(text: "Allow running npm test in /fictional/orbit?\n\n1. Yes, once\n2. Yes, for this session\n3. No", token: nil, question: nil)), nil); settle()
    verify(panel.model.agents.attention?.text.contains("npm test") == true, "Waiting question appears at the top of the herdr view")
    try render("attention")
    panel.model.agents.sessions = [waitingCodex]; settle()
    verify(panel.model.agents.attention == nil && panel.model.agents.attentionLoading, "Changing waiting agent clears the previous question")
    let codexQuestionText = """
    Question 1/1 (1 unanswered)
    Which fictional theme should the demo use?

    › 1. Amber              warm colors
      2. Violet             cool colors
      3. None of the above  Optionally, add details in notes (tab).

    tab to add notes | enter to submit answer | esc to interrupt
    """
    let codexQuestion = HerdrQuestion.parse(codexQuestionText, provider: "codex")!
    previewReply?(try JSONEncoder().encode(HerdrResponseController.Snapshot(text: codexQuestionText, token: "fictional-token", question: codexQuestion)), nil); settle()
    verify(panel.model.agents.canAnswerAttention, "Verified Codex question enables answers")
    try render("attention-choices")
    var answered: [Int] = []
    var answerReply: ((String?, String?) -> Void)?
    panel.model.agents.attentionResponder = { token, choice, reply in
        verify(token == "fictional-token", "Response binds the displayed question token")
        answered.append(choice); answerReply = reply
    }
    // Native click on Answer with keyboard; card geometry is fixed above the scrollable results.
    click(at: NSPoint(x: 90, y: panel.contentView!.bounds.height - 234))
    key("2", 19, [.command, .option])
    verify(answered == [2], "Focused question shortcut sends the selected answer")
    panel.model.agents.answerAttention(2)
    verify(answered == [2] && !panel.model.agents.canAnswerAttention, "Duplicate clicks cannot send a second answer")
    try render("attention-sending")
    answerReply?("Answer sent; Codex resumed.", nil); settle()
    verify(panel.model.agents.attentionResponse == "Answer sent; Codex resumed.", "Delivery feedback shows provider acknowledgement")
    try render("attention-answered")
    panel.model.agents.refreshAttention()
    previewReply?(nil, "This question changed or could not be read. Open the pane in Herdr to review it."); settle()
    verify(panel.model.agents.attentionError == nil && panel.model.agents.attentionResponse != nil, "Post-answer refresh cannot replace delivery feedback with a stale error")
    try render("attention-transition")
    panel.model.agents.watchAttention(nil); panel.model.agents.watchAttention(waitingCodex)
    previewReply?(nil, "This question changed or could not be read. Open the pane in Herdr to review it."); settle()
    try render("attention-error")
    // Claude uses its own observed screen, including the complete approval scope.
    panel.model.agents.sessions = [waitingClaude]; settle()
    let claudePermissionText = """
    ─────────────────────────────────────────────
     Create file
     /fictional/approval.txt
    ╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌
      1 Violet demo
    ╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌
     Do you want to create approval.txt?
     ❯ 1. Yes
       2. Yes, and switch to accept edits (auto-approve file edits and common file
          commands) for this session (shift+tab)
       3. No

     Esc to cancel · Tab to amend
    """
    let claudePermission = HerdrQuestion.parse(claudePermissionText, provider: "claude")!
    previewReply?(try JSONEncoder().encode(HerdrResponseController.Snapshot(text: claudePermissionText, token: "fictional-token", question: claudePermission)), nil); settle()
    verify(panel.model.agents.canAnswerAttention, "Claude approval exposes the verified choices")
    try render("attention-claude-approval")
    func nativeScrollViews(_ view: NSView) -> [NSScrollView] {
        (view as? NSScrollView).map { [$0] } ?? view.subviews.flatMap(nativeScrollViews)
    }
    if let scroll = nativeScrollViews(panel.contentView!).first, let document = scroll.documentView {
        scroll.contentView.scroll(to: NSPoint(x: 0, y: max(0, document.bounds.height - scroll.contentSize.height)))
        scroll.reflectScrolledClipView(scroll.contentView); settle()
    }
    try render("attention-claude-scope")
    click(at: NSPoint(x: 90, y: panel.contentView!.bounds.height - 286))
    key("3", 20, [.command, .option])
    verify(answered == [2, 3], "Claude No shortcut delivers only the selected denial")
    answerReply?("Answer sent; Claude Code resumed.", nil); settle()
    try render("attention-claude-answered")
    panel.model.agents.sessions = []; settle()
    verify(panel.model.agents.attention == nil, "Resolved questions remove the preview")
    try render("attention-empty")
    // Equal pane IDs remain independently searchable by machine.
    let localTwin = AgentSession(agent: "codex", agentStatus: "working", paneID: "w1:p1", terminalID: "same-pane", cwd: "/fictional/shared", terminalTitle: nil, agentSession: nil)
    var remoteTwin = localTwin; remoteTwin.machine = waitingClaude.machine
    panel.model.agents.sessions = [localTwin, remoteTwin]
    panel.model.query = "agents Build Mac"; settle()
    verify(panel.model.rows.count == 1 && panel.model.rows.first?.id == ResultRow.agentSession(remoteTwin).id, "Machine search selects only the remote pane with a colliding ID")
    try render("machines-filtered")
    panel.model.query = "agents"; settle()
    verify(panel.model.rows.count == 2, "Local and remote panes with identical IDs remain separate rows")
    try render("machines-overview")
    // The footer status replaces the old strip: it counts waiting panes and names an unavailable machine.
    panel.model.agents.sessions = [waitingClaude, waitingCodex]
    panel.model.query = ""; settle()
    verify(HerdrStatusSummary(sessions: panel.model.agents.sessions, connected: true, busy: false, machines: panel.model.agents.machines).text == "Herdr: 2 waiting", "Footer counts both waiting panes")
    try render("herdr-footer-waiting")
    panel.model.agents.sessions = [localTwin]; settle()
    verify(HerdrStatusSummary(sessions: panel.model.agents.sessions, connected: true, busy: false, machines: panel.model.agents.machines).text == "Herdr: Lab unavailable", "Footer names the unavailable machine when nothing waits")
    try render("herdr-footer-unavailable")
    panel.orderOut(nil)
    print("PASS: passive Herdr question previews, target changes, loading, error, and resolved states")
}

/// API and local-server Settings with fictional discovery and credentials, never host services or
/// owner keys, then a local-model conversation in the standalone chat view.
func apiSettingsScenario() throws {
    let aiFixtureURL = try aiSettingsFile()
    func renderAPISettings(_ kind: AIConnectionKind, provider: AIAPIProvider = .openAI, offline: Bool = false) throws {
        var config = AIConfiguration(); config.connection = kind; config.api.provider = provider; config.api.endpoint = provider.endpoint
        try config.save(at: aiFixtureURL)
        let discovery = AIModelDiscovery()
        discovery.lookupOverride = { candidate, _, completion in
            if candidate.endpoint.contains("11434") && !offline { completion(["fictional-local-model", "fictional-second-model"], nil) }
            else { completion(nil, "Server unavailable. Start it or enter a custom URL.") }
        }
        let conversations = ACPConversations()
        let model = conversations.current
        let (window, view) = hostWindow(AISettingsView(conversations: conversations, configURL: aiFixtureURL, onChange: {}, openConversation: { _ in }, chooseProject: { _ in }, credentials: fakeCredentials, discovery: discovery),
                                        width: 480, height: 660)
        try render("ai-\(kind.rawValue)-\(provider.rawValue)\(offline ? "-offline" : "")", view: view)
        verify(!model.active && credentialWrites == 0, "Opening AI Settings never starts chat or writes credentials")
        if kind == .local && !offline {
            guard let use = controlFrame("settings.use-server", in: window) else { verify(false, "Local server offers Use"); return }
            click(at: NSPoint(x: use.midX, y: use.midY), in: window, downPressure: 1)
            verify(try! AIConfiguration.load(at: aiFixtureURL).localAPI.model == "fictional-local-model", "Use persists the discovered local model")
            verify(discovery.models.count == 2, "Use keeps the discovered model picker populated")
            try render("ai-local-selected", view: view)
        }
        window.orderOut(nil); discovery.cancel()
    }
    try renderAPISettings(.byok)
    try renderAPISettings(.byok, provider: .anthropic)
    try renderAPISettings(.byok, provider: .compatible)
    try renderAPISettings(.local)
    try renderAPISettings(.local, offline: true)
    let apiModel = ACPModel()
    var localConfig = AIConfiguration(); localConfig.connection = .local; localConfig.localAPI.model = "Fictional local model"
    apiModel.configure(localConfig); apiModel.state.phase = "ready"
    apiModel.state.messages = [ACPMessage(role: "You", text: "Show a fictional example"), ACPMessage(role: "Agent", text: "**Hello** from a local model.\n\n- Runs on your machine\n- Uses the same chat controls")]
    let (apiChatWindow, apiChat) = hostWindow(ACPConversationView(model: apiModel), width: 740, height: 450)
    try render("ai-local-chat", view: apiChat)
    apiChatWindow.orderOut(nil)
    apiModel.state.phase = "disconnected"
    print("PASS: BYOK/local Settings and chat fixtures use no real servers or credentials")
}

/// ACP detection renders a fictional result; the real helper and the owner's installs are never read.
func acpDetectionScenario() throws {
    let aiFixtureURL = try aiSettingsFile()
    var config = AIConfiguration(); config.connection = .acp; config.provider = "claude"
    try config.save(at: aiFixtureURL)
    let detection = ACPAgentDetection()
    detection.reader = { reply in
        reply(try? JSONEncoder().encode([
            ACPAgentAvailability(provider: "claude", state: .ready, detail: "Found at ~/.local/bin/claude", path: "/Users/fixture/.local/bin/claude"),
            ACPAgentAvailability(provider: "qwen", state: .ready, detail: "Found at /opt/homebrew/bin/qwen", path: "/opt/homebrew/bin/qwen"),
            ACPAgentAvailability(provider: "codex", state: .needsAdapter, detail: "Codex’s ACP adapter is missing. Install Volant’s ACP adapters and retry.", path: nil),
            ACPAgentAvailability(provider: "gemini", state: .notInstalled, detail: "Gemini CLI was not found. Install it and sign in, then retry.", path: nil)
        ]), nil)
    }
    let conversations = ACPConversations()
    let model = conversations.current
    let view = NSHostingView(rootView: AISettingsView(conversations: conversations, configURL: aiFixtureURL, onChange: {}, openConversation: { _ in }, chooseProject: { _ in },
                                                      credentials: fakeCredentials, discovery: AIModelDiscovery(), agentDetection: detection)
        .background(Color(nsColor: .windowBackgroundColor)))
    let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 480, height: 760), styleMask: [.titled], backing: .buffered, defer: false)
    window.contentView = view; window.makeKeyAndOrderFront(nil)
    verify(waitUntil { detection.agents.map(\.provider) == ["claude", "qwen", "codex", "gemini"] },
           "Detected agents list ready providers first, saw \(detection.agents.map(\.provider))")
    settle()
    try render("ai-acp-detected", view: view)
    guard let use = controlFrame("settings.use-agent-qwen", in: window) else { verify(false, "A ready agent offers Use"); exit(1) }
    click(at: NSPoint(x: use.midX, y: use.midY), in: window, downPressure: 1)
    verify(try! AIConfiguration.load(at: aiFixtureURL).provider == "qwen", "Use saves a detected provider")
    verify(!model.active, "Choosing a detected agent never connects")
    try render("ai-acp-detected-selected", view: view)
    window.orderOut(nil)
    print("PASS: detected ACP agents render, sort and select without connecting")
}

/// A recorded ACP conversation offers Resume and New in the standalone chat view without connecting.
func acpResumeScenario() throws {
    let resumeSuite = "volant.actions.fixture.acp-resume"
    UserDefaults().removePersistentDomain(forName: resumeSuite)
    let resumeStore = UserDefaults(suiteName: resumeSuite)!
    resumeStore.set(try JSONEncoder().encode(ACPResumeRecord(provider: "claude", project: "", sessionID: "fictional-session")), forKey: ACPModel.resumeKey)
    let resumeModel = ACPModel(resumeStore: resumeStore)
    var resumeConfig = AIConfiguration(); resumeConfig.provider = "claude"
    var resumeConnects = 0
    verify(resumeModel.openChat(configuration: resumeConfig) { resumeConnects += 1 } && resumeConnects == 0 && resumeModel.canResume, "Opening chat offers Resume without connecting")
    let (resumeChatWindow, resumeChat) = hostWindow(ACPConversationView(model: resumeModel), width: 740, height: 450)
    try render("ai-acp-resume", view: resumeChat)
    resumeChatWindow.orderOut(nil)
    UserDefaults().removePersistentDomain(forName: resumeSuite)
    print("PASS: a recorded ACP conversation offers Resume and New without connecting")
}

/// Several conversations in one list, drawn in the standalone chat view, activity strip and AI
/// Settings. Starting one only marks it ready and detection reads a fictional result, so no helper
/// connection opens.
func acpSeveralScenario() throws {
    let aiFixtureURL = try aiSettingsFile()
    let severalSuite = "volant.actions.fixture.acp-several"
    UserDefaults().removePersistentDomain(forName: severalSuite)
    let several = ACPConversations(make: { ACPModel(resumeStore: UserDefaults(suiteName: severalSuite)!) },
                                   start: { model in model.state.phase = "ready"; model.state.status = "Ready" })
    var severalConfig = AIConfiguration(); severalConfig.provider = "claude"; severalConfig.project = "/fictional/orbit-web"
    verify(several.newConversation(configuration: severalConfig), "An unused conversation starts in place")
    let severalAwaiting = several.current
    severalAwaiting.state.phase = "working"; severalAwaiting.state.status = "Needs your permission"
    severalAwaiting.state.permissions = [ACPPermission(id: "fictional-permission", title: "Read fictional notes", detail: "{}",
                                                       options: [ACPPermission.Option(optionId: "once", name: "Allow once", kind: "allow_once")])]
    severalConfig.provider = "codex"
    verify(several.newConversation(configuration: severalConfig) && several.live.count == 2 && severalAwaiting.active, "New keeps the first conversation running")
    several.current.state.messages = [ACPMessage(role: "You", text: "Summarize the fictional release notes."),
                                      ACPMessage(role: "Agent", text: "The fictional release adds **two** settings.")]
    verify(several.nextToOpen === severalAwaiting && severalAwaiting.background && !several.current.background,
           "The launcher opens the conversation awaiting permission first, and only the shown one polls at the foreground interval")
    let (severalChatWindow, severalChat) = hostWindow(ACPConversationView(model: several.current, conversations: several), width: 740, height: 450)
    try render("ai-acp-several", view: severalChat)
    severalChatWindow.orderOut(nil)
    let (severalStripWindow, severalStrip) = hostWindow(VStack(spacing: 0) {
        ACPActivityStrip(conversations: several) { _ in }
        Spacer(minLength: 0)
    }, width: 740, height: 60)
    try render("ai-acp-several-strip", view: severalStrip)
    severalStripWindow.orderOut(nil)
    try severalConfig.save(at: aiFixtureURL)
    let severalDetection = ACPAgentDetection()
    severalDetection.reader = { reply in
        reply(try? JSONEncoder().encode([ACPAgentAvailability(provider: "codex", state: .ready, detail: "Found at /opt/homebrew/bin/codex", path: "/opt/homebrew/bin/codex")]), nil)
    }
    let (severalSettingsWindow, severalSettings) = hostWindow(AISettingsView(conversations: several, configURL: aiFixtureURL, onChange: {}, openConversation: { _ in }, chooseProject: { _ in },
                                                                             credentials: fakeCredentials, discovery: AIModelDiscovery(), agentDetection: severalDetection),
                                                              width: 480, height: 760)
    verify(several.live.count == 2 && several.current.active, "AI Settings is drawn with two running conversations")
    try render("ai-acp-several-settings", view: severalSettings)
    severalSettingsWindow.orderOut(nil)
    for model in several.all { model.state.phase = "disconnected" }
    UserDefaults().removePersistentDomain(forName: severalSuite)
    print("PASS: several ACP conversations render their buttons and activity strip without a helper connection")
}

/// Accounts in AI Settings, the chat header, the conversation buttons and the activity strip. The
/// profiles name fictional folders and no helper connection opens, so no folder is read and no
/// provider starts. Three conversations run: Claude Code under Work, Codex under its default login,
/// and Claude Code under Personal.
func acpAccountsScenario() throws {
    let aiFixtureURL = try aiSettingsFile()
    let accountsSuite = "volant.actions.fixture.acp-accounts"
    UserDefaults().removePersistentDomain(forName: accountsSuite)
    var accountsConfig = AIConfiguration(); accountsConfig.provider = "claude"
    try accountsConfig.addProfile(ACPAccountProfile(provider: "claude", label: "Work", directory: "/tmp/fictional-claude-work"))
    try accountsConfig.addProfile(ACPAccountProfile(provider: "claude", label: "Personal", directory: "/tmp/fictional-claude-personal"))
    try accountsConfig.addProfile(ACPAccountProfile(provider: "codex", label: "Work", directory: "/tmp/fictional-codex-work"))
    accountsConfig.chooseAccount(accountsConfig.profiles(for: "claude").first?.id, for: "claude")
    try accountsConfig.save(at: aiFixtureURL)
    let accountsList = ACPConversations(make: { ACPModel(resumeStore: UserDefaults(suiteName: accountsSuite)!) },
                                        start: { model in model.state.phase = "ready"; model.state.status = "Ready" })
    var accountFoldersChosen = 0
    let accountsDetection = ACPAgentDetection()
    accountsDetection.reader = { reply in
        reply(try? JSONEncoder().encode([ACPAgentAvailability(provider: "claude", state: .ready, detail: "Found at ~/.local/bin/claude", path: "/Users/fixture/.local/bin/claude")]), nil)
    }
    let (accountsSettingsWindow, accountsSettings) = hostWindow(AISettingsView(conversations: accountsList, configURL: aiFixtureURL, onChange: {}, openConversation: { _ in }, chooseProject: { _ in },
                                                                               chooseAccountFolder: { _ in accountFoldersChosen += 1 },
                                                                               credentials: fakeCredentials, discovery: AIModelDiscovery(), agentDetection: accountsDetection),
                                                                width: 480, height: 900)
    verify(controlFrame("settings.add-account", in: accountsSettingsWindow) != nil && accountFoldersChosen == 0 && !accountsList.current.active,
           "AI Settings lists the Claude Code accounts without choosing a folder or connecting")
    try render("ai-acp-accounts-settings", view: accountsSettings)
    accountsSettingsWindow.orderOut(nil)
    verify(accountsList.newConversation(configuration: accountsConfig), "A conversation starts under Work")
    let accountsWork = accountsList.current
    accountsWork.state.messages = [ACPMessage(role: "You", text: "Summarize the fictional release notes."),
                                   ACPMessage(role: "Agent", text: "The fictional release adds **two** settings.")]
    var accountsCodex = accountsConfig; accountsCodex.provider = "codex"
    verify(accountsList.newConversation(configuration: accountsCodex), "A Codex conversation starts under its default login")
    var accountsPersonal = accountsConfig; accountsPersonal.chooseAccount(accountsConfig.profiles(for: "claude").last?.id, for: "claude")
    verify(accountsList.newConversation(configuration: accountsPersonal), "A conversation starts under Personal")
    let accountsShown = accountsList.current
    accountsShown.state.messages = [ACPMessage(role: "You", text: "List the open risks in the fictional release notes.")]
    let accountsDefault = accountsList.all.filter { $0.account == nil }.map(\.provider)
    verify(accountsWork.account?.label == "Work" && accountsShown.account?.label == "Personal" && accountsDefault == ["codex"],
           "Each conversation keeps the account it started with")
    let (accountsChatWindow, accountsChat) = hostWindow(ACPConversationView(model: accountsShown, conversations: accountsList), width: 740, height: 450)
    try render("ai-acp-accounts", view: accountsChat)
    accountsChatWindow.orderOut(nil)
    let (accountsStripWindow, accountsStrip) = hostWindow(VStack(spacing: 0) {
        ACPActivityStrip(conversations: accountsList) { _ in }
        Spacer(minLength: 0)
    }, width: 740, height: 60)
    try render("ai-acp-accounts-strip", view: accountsStrip)
    accountsStripWindow.orderOut(nil)
    for model in accountsList.all { model.state.phase = "disconnected" }
    UserDefaults().removePersistentDomain(forName: accountsSuite)
    print("PASS: accounts render in AI Settings, the chat header, the conversation buttons and the launcher row without a helper connection")
}

/// Clipboard failures never access the owner's Keychain or pasteboard. A real SwiftUI command
/// equivalent invokes the native Retry button, which restores preserved history.
func clipboardRecoveryScenario() throws {
    clipboard.record("Fictional clipboard recovery fixture")
    verify(!clipboard.recent().isEmpty, "Fixture clipboard row persisted")
    clipboardAvailable = false
    clipboard.retry(); settle()
    panel.toggle(); settle(); panel.model.query = "clip"; settle()
    verify(panel.model.clipboardMessage != nil && panel.model.rows.isEmpty, "Clipboard failure is distinct from empty history")
    try render("clipboard-unavailable")
    clipboardAvailable = true; clipboardRetryDelay = 0.8
    key("r", 15, .command)
    verify(panel.model.clipboardRetrying, "Command R activates clipboard Retry")
    try render("clipboard-retrying")
    let clipboardDeadline = Date().addingTimeInterval(5)
    while (panel.model.clipboardRetrying || panel.model.rows.isEmpty) && Date() < clipboardDeadline {
        RunLoop.main.run(until: Date().addingTimeInterval(0.02))
    }
    verify(panel.model.clipboardMessage == nil && !panel.model.rows.isEmpty, "Retry restores preserved clipboard history")
    try render("clipboard-recovered")
    panel.model.query = "clip no-fixture-match"; settle()
    verify(panel.model.notice == "No matching clipboard items" && panel.model.clipboardMessage == nil, "A healthy empty search offers no error or Retry")
    try render("clipboard-no-match")
    panel.orderOut(nil)
    print("PASS: clipboard error, native Retry shortcut, progress, retained history and empty search")
}

/// Refused Spotlight starts keep useful results and expose a native Retry action.
func spotlightRecoveryScenario() throws {
    index.start()
    panel.toggle(); settle(); panel.model.query = "Fixture"; settle()
    verify(panel.model.searchRecoveryMessage != nil && !panel.model.rows.isEmpty, "App discovery failure coexists with existing rows")
    try render("spotlight-app-unavailable")
    spotlightAvailable = true
    key("r", 15, .command)
    verify(panel.model.searchRecoveryMessage == nil, "Native Retry restarts app discovery")
    panel.model.query = "/fictional"
    verify(waitUntil { panel.model.filesUnavailable }, "Refused file query produces a visible failure")
    try render("spotlight-file-unavailable")
    key("r", 15, .command); settle()
    verify(panel.model.filesUnavailable, "A repeated failure remains retryable")
    panel.model.query = "clip"; settle()
    verify(panel.model.searchRecoveryMessage == nil, "Search errors do not leak into another command")
    panel.orderOut(nil)
    print("PASS: Spotlight refusal and native Retry keep existing results and stay within their command")
}

/// An unreadable note stays selectable with a read-only placeholder, the browser opens over it, and
/// native Retry reloads the repaired file. The notes panel has its own size, independent of the
/// launcher's, so this runs only at the default launcher size.
func notesRecoveryScenario() throws {
    let recoveryNotes = NotesStore(directory: root.appendingPathComponent("recovery-notes-\(UUID().uuidString)"))
    let damagedURL = recoveryNotes.directory.appendingPathComponent("Fictional travel plans.md")
    try Data([0xFF, 0xFE, 0xFA]).write(to: damagedURL)
    recoveryNotes.reload()
    let recoveryPanel = NotesPanel(store: recoveryNotes)
    recoveryPanel.setContentSize(NSSize(width: 560, height: 620))
    recoveryPanel.open(noteID: damagedURL.lastPathComponent); settle()
    verify(recoveryNotes.notes.first?.readError != nil, "Unreadable note remains selectable")
    try render("notes-unreadable", view: recoveryPanel.contentView!)
    func notesKey(_ text: String, _ code: UInt16) {
        let event = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: .command,
            timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: recoveryPanel.windowNumber,
            context: nil, characters: text, charactersIgnoringModifiers: text, isARepeat: false, keyCode: code)!
        verify(recoveryPanel.performKeyEquivalent(with: event), "Notes keyboard shortcut is handled")
        settle()
    }
    notesKey("p", 35)
    try render("notes-unreadable-browser", view: recoveryPanel.contentView!)
    recoveryPanel.cancelOperation(nil); settle()
    try "# Fictional travel plans\n\nRepaired Markdown note.".write(to: damagedURL, atomically: true, encoding: .utf8)
    notesKey("r", 15)
    verify(recoveryNotes.loadMessage == nil && recoveryNotes.notes.first?.readError == nil, "Native Notes Retry reloads repaired text")
    try render("notes-recovered", view: recoveryPanel.contentView!)
    recoveryPanel.close()
    print("PASS: unreadable Notes recovery with native keyboard controls")
}

/// Rex in the launcher: fictional panes through an injected watcher reader, waiting ones first, a
/// term that filters them, Return focusing through a fake and stopping the watcher, the footer count,
/// and the not-running message. No Rex server or agent helper is reached.
func rexScenario() throws {
    func pane(_ block: String, session: String, label: String, folder: String, state: RexState, message: String?) -> RexPane {
        RexPane(sessionID: "session:" + session, sessionLabel: label, blockID: "block:" + block, label: "shell", cwd: "/fictional/" + folder,
                status: RexStatus(state: state, kind: state == .blocked ? "permission" : nil, app: "claude-code", message: message))
    }
    let panes = RexInventory.sorted([
        pane("b1", session: "fixture-web", label: "web", folder: "comet", state: .working, message: "Running the test suite"),
        pane("b2", session: "fixture-api", label: "api", folder: "orbit", state: .blocked, message: "Allow running the migration?"),
        pane("b3", session: "fixture-api", label: "api", folder: "orbit-docs", state: .done, message: "Updated three pages"),
        pane("b4", session: "fixture-ops", label: "ops", folder: "deploy", state: .error, message: "Build failed"),
    ])
    var reply: ((Data?, Int, String?) -> Void)?
    var focused: [String] = []
    var stops = 0
    panel.model.rex.reader = { _, next in reply = next }
    panel.model.rex.stopper = { stops += 1 }
    panel.model.rex.focuser = { pane, done in focused.append(pane.id); done(nil) }
    panel.model.rex.activateRex = {}
    panel.model.config.statusBar.sources = ["rex"]
    summon()
    panel.model.query = "rex"
    verify(waitUntil { panel.model.rex.connected && reply != nil }, "The rex view starts reading without a Connect step")
    reply?(try JSONEncoder().encode(RexInventory(panes: panes)), 1, nil); settle()
    verify(waitUntil { panel.model.rows.filter { if case .rexPane = $0 { return true } else { return false } }.count == 4 }, "Every fictional Rex pane is listed")
    verify(panel.model.rows.first?.id == "command:rex-overview", "Open Rex Overview is first")
    verify(panel.model.rows.dropFirst().first?.id == "rex:session:fixture-api/block:b2", "The waiting pane leads the panes")
    try render("rex-panes")
    panel.model.query = "rex build"; settle()
    verify(panel.model.rows.map(\.id) == ["rex:session:fixture-ops/block:b4"], "A trailing term filters by message")
    key("\r", 36)
    verify(waitUntil { focused == ["session:fixture-ops/block:b4"] }, "Return focuses the selected pane by its stable identity")
    verify(stops == 1, "Dismissing the launcher stops the Rex watcher")
    reply = nil
    summon()
    panel.model.query = "rex"
    verify(waitUntil { reply != nil }, "Showing the rex view again reads again")
    reply?(nil, 1, "Rex isn’t running. Open Rex, then try again."); settle()
    verify(waitUntil { panel.model.rows.isEmpty && panel.model.notice == "Rex isn’t running. Open Rex, then try again." }, "A stopped Rex says so")
    try render("rex-not-running")
    panel.model.config.statusBar.sources = []
    print("PASS: rex lists fictional panes waiting first, filters, focuses by identity and reports a stopped server")
}

/// The Rex Overview window with fictional sessions: the approval card, then pane previews from
/// invented screen text. The choice is saved to a fake, and no Rex server or agent helper is reached.
func rexOverviewScenario() throws {
    func status(_ state: RexState, _ message: String?) -> RexStatus { RexStatus(state: state, app: "claude-code", message: message) }
    let overview = RexOverview(sessions: [
        .init(sessionID: "session:fixture-orbit", label: "orbit", tabs: [
            .init(windowID: "window:orbit-api", label: "api", active: true, focusedBlockID: "block:orbit-agent", panes: [
                .init(blockID: "block:orbit-agent", label: "shell", title: "orbit-api", program: "claude", status: status(.blocked, "Allow running the migration?"), rect: [0, 0, 0.6, 1],
                      preview: ["  Edited db/migrate/0042_add_flights.sql", "", "  Run the migration against the dev database?", "", "  › 1. Yes", "    2. Yes, and don’t ask again for psql", "    3. No, tell Claude what to do differently"]),
                .init(blockID: "block:orbit-logs", label: "logs", title: "server log", program: "tail", status: RexStatus(state: .working), rect: [0.6, 0, 0.4, 0.5],
                      preview: ["GET /flights 200 12ms", "GET /flights/OR42 200 4ms", "POST /bookings 201 31ms", "GET /health 200 1ms"]),
                .init(blockID: "block:orbit-shell", label: "shell", title: "~/orbit", program: "zsh", rect: [0.6, 0.5, 0.4, 0.5],
                      preview: ["~/orbit main ✓", "$ git status --short", " M db/migrate/0042_add_flights.sql", "~/orbit main ✗ $"]),
            ]),
            .init(windowID: "window:orbit-web", label: "web", focusedBlockID: "block:orbit-web", panes: [
                .init(blockID: "block:orbit-web", label: "shell", title: "orbit-web", program: "claude", status: status(.done, "Updated the booking form and its tests"), rect: [0, 0, 1, 1],
                      preview: ["  ✓ Updated src/booking/Form.tsx", "  ✓ Added 6 tests in Form.test.tsx", "", "  All 214 tests pass.", "", "  >"]),
            ]),
        ]),
        .init(sessionID: "session:fixture-comet", label: "comet", tabs: [
            .init(windowID: "window:comet-build", label: "build", active: true, focusedBlockID: "block:comet-cargo", panes: [
                .init(blockID: "block:comet-cargo", label: "shell", title: "cargo build", program: "cargo", status: RexStatus(state: .working, app: "cargo", message: "Compiling comet-core", progress: 64), rect: [0, 0, 1, 0.55],
                      preview: ["   Compiling serde v1.0.219", "   Compiling tokio v1.45.0", "   Compiling comet-net v0.4.2", "   Compiling comet-core v0.9.0", "    Building [=======>    ] 118/184"]),
                .init(blockID: "block:comet-test", label: "shell", title: "~/comet", program: "zsh", rect: [0, 0.55, 1, 0.45],
                      preview: ["~/comet $ just test-watch", "watching 41 files…"]),
            ]),
        ]),
        .init(sessionID: "session:fixture-ops", label: "ops", tabs: [
            .init(windowID: "window:ops-deploy", label: "deploy", active: true, focusedBlockID: "block:ops-deploy", panes: [
                .init(blockID: "block:ops-deploy", label: "shell", title: "deploy staging", program: "terraform", status: RexStatus(state: .error, app: "terraform", message: "Apply failed: quota exceeded"), rect: [0, 0, 1, 1],
                      preview: ["module.cache.aws_elasticache_cluster.main: Creating...", "", "Error: creating ElastiCache Cluster: quota exceeded", "", "  with module.cache.aws_elasticache_cluster.main,", "  on cache/main.tf line 12"]),
            ]),
            .init(windowID: "window:ops-notes", label: "Window 3f2a91c0", focusedBlockID: "block:ops-shell", panes: [
                .init(blockID: "block:ops-shell", label: "shell", title: "~/ops", program: "zsh", rect: [0, 0, 1, 1], preview: ["~/ops $"]),
            ]),
        ]),
    ])
    var saved: [Bool] = []
    let minimizedSuite = "com.mysticcoders.volant.actionsfixture.rex-overview"
    let minimizedDefaults = UserDefaults(suiteName: minimizedSuite)!
    minimizedDefaults.removePersistentDomain(forName: minimizedSuite)
    defer { minimizedDefaults.removePersistentDomain(forName: minimizedSuite) }
    let model = RexOverviewModel(previewsAllowed: false, save: { saved.append($0) }, defaults: minimizedDefaults)
    model.show(overview)
    let controller = RexOverviewWindowController(model: model)
    let window = controller.window!
    window.setFrame(NSWindow.frameRect(forContentRect: NSRect(x: 0, y: 0, width: 980, height: 640), styleMask: window.styleMask), display: false)
    window.orderFront(nil); settle()
    verify(!model.previewsAllowed, "The overview asks before reading screens")
    try render("rex-overview-consent", view: window.contentView!)
    model.allowPreviews(true)
    model.show(overview); settle()
    verify(model.previewsAllowed && saved == [true], "Approving inline saves the choice")
    try render("rex-overview-preview", view: window.contentView!)
    var focusedPanes: [String] = []
    model.focuser = { session, block, done in focusedPanes.append(session + "/" + block); done(nil) }
    model.activateRex = {}
    func press(_ code: UInt16, _ characters: String, _ modifiers: NSEvent.ModifierFlags = []) {
        let event = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: modifiers, timestamp: ProcessInfo.processInfo.systemUptime,
                                     windowNumber: window.windowNumber, context: nil, characters: characters, charactersIgnoringModifiers: characters,
                                     isARepeat: false, keyCode: code)!
        window.sendEvent(event); settle()
    }
    verify(model.selection?.blockID == "block:orbit-agent", "Selection starts on the waiting pane")
    press(125, "\u{F701}")
    verify(model.selection?.blockID == "block:orbit-logs", "Down moves to the next pane in the split tab")
    press(124, "\u{F703}")
    verify(model.selection?.blockID == "block:orbit-web", "Right moves to the next tab card")
    press(123, "\u{F702}"); press(125, "\u{F701}"); press(125, "\u{F701}")
    verify(model.selection?.blockID == "block:orbit-shell", "Left returns to the split tab, then down reaches its last pane")
    try render("rex-overview-keyboard", view: window.contentView!)
    press(48, "\t")
    verify(model.selection?.blockID == "block:orbit-agent", "Tab wraps to the waiting pane")
    press(36, "\r")
    verify(focusedPanes == ["session:fixture-orbit/block:orbit-agent"], "Return focuses the selected pane through the window's keys")
    let layers = RexOverview(sessions: [
        .init(sessionID: "session:fixture-lab", label: "lab", tabs: [
            .init(windowID: "window:lab-float", label: "monitor", active: true, focusedBlockID: "block:lab-top", panes: [
                .init(blockID: "block:lab-editor", label: "shell", title: "notes.md", program: "nvim", rect: [0, 0, 0.55, 1],
                      preview: ["## Launch checklist", "- [x] staging smoke test", "- [ ] DNS cutover", "- [ ] tell support"]),
                .init(blockID: "block:lab-server", label: "shell", title: "dev server", program: "node", status: RexStatus(state: .working, app: "vite", message: "Serving on :5173"), rect: [0.55, 0, 0.45, 1],
                      preview: ["VITE v6.3.1  ready in 412 ms", "➜  Local:   http://localhost:5173/", "page reload src/App.tsx"]),
                .init(blockID: "block:lab-top", label: "shell", title: "htop", program: "htop", rect: [0.35, 0.45, 0.4, 0.5], preview: ["CPU [||||      28%]", "Mem [|||||  6.1G/16G]", "  PID USER  %CPU COMMAND", "41201 dev   22.0 node"], layer: 1),
                .init(blockID: "block:lab-clock", label: "shell", title: "timer", program: "watch", rect: [0.78, 0.06, 0.18, 0.22], preview: ["00:14:32"], layer: 2),
            ]),
            .init(windowID: "window:lab-zoom", label: "release", focusedBlockID: "block:lab-zoomed", panes: [
                .init(blockID: "block:lab-zoomed", label: "shell", title: "release notes", program: "claude", status: RexStatus(state: .working, app: "claude-code", message: "Drafting the notes"), rect: [0, 0, 0.5, 1],
                      preview: ["  Reading docs/releases/", "  Drafting 0.4.0 notes…"]),
                .init(blockID: "block:lab-tests", label: "shell", title: "tests", program: "cargo", status: RexStatus(state: .error, app: "cargo", message: "2 tests failed"), rect: [0.5, 0, 0.5, 0.5]),
                .init(blockID: "block:lab-logs", label: "shell", title: "logs", program: "tail", status: RexStatus(state: .working), rect: [0.5, 0.5, 0.25, 0.5]),
                .init(blockID: "block:lab-shell", label: "shell", title: "~/lab", program: "zsh", rect: [0.75, 0.5, 0.25, 0.5]),
            ], zoomedBlockID: "block:lab-zoomed"),
        ]),
    ])
    model.show(layers); settle()
    model.select(.init(sessionID: "session:fixture-lab", blockID: "block:lab-zoomed"))
    press(125, "\u{F701}"); settle()
    verify(model.selection?.blockID == "block:lab-tests", "Down from the zoomed pane reaches the first hidden pane")
    press(123, "\u{F702}")
    verify(model.selection?.blockID == "block:lab-top", "Entering a tab lands on the pane Rex focuses, here a floating one")
    press(125, "\u{F701}")
    verify(model.selection?.blockID == "block:lab-clock", "Down moves from the back floating layer to the front one")
    press(126, "\u{F700}"); press(126, "\u{F700}")
    verify(model.selection?.blockID == "block:lab-server", "Up moves from the floating layers back to the tiles")
    press(124, "\u{F703}"); press(125, "\u{F701}")
    verify(model.selection?.blockID == "block:lab-tests", "Selection can rest on a hidden pane")
    try render("rex-overview-layers", view: window.contentView!)
    model.show(overview); settle()
    model.select(.init(sessionID: "session:fixture-orbit", blockID: "block:orbit-web"))
    press(49, " ")
    verify(model.minimizedSessions == ["session:fixture-orbit"], "Space minimizes the selected session through the window's keys")
    try render("rex-overview-minimized", view: window.contentView!)
    press(124, "\u{F703}")
    verify(model.selection?.sessionID == "session:fixture-comet", "Right leaves a minimized session in one step")
    press(123, "\u{F702}"); press(49, " ")
    verify(model.minimizedSessions.isEmpty, "Space expands it again")
    model.allowPreviews(false); settle()
    verify(saved == [true, false] && model.overview.sessions.isEmpty, "Turning previews off saves the choice and forgets the screen text")
    window.orderOut(nil)
    print("PASS: Rex Overview asks first, renders previews from fictional sessions, moves and focuses by keyboard, and forgets them when turned off")
}

/// A scenario runs against a fresh hidden launcher. Size-sensitive scenarios render or click inside
/// the `LauncherPanel`, whose layout follows the launcher size, and run at every size; the rest run
/// only at the default size.
struct Scenario {
    let name: String
    let sizeSensitive: Bool
    let run: () throws -> Void
}

/// Size-sensitive, because they draw or click in the launcher panel:
/// - actions: the action menu, and a mouse click whose row position is derived from the panel size.
/// - volant-menu: the footer mark click and the menu drawn inside the panel.
/// - panel-chat: the chat surface, @ picker and Back button inside the panel. Its AI Settings window
///   follows from the live conversation and is drawn only at the default size by `render`.
/// - community-launcher: blocked and first-use extension rows in the panel; consent bookkeeping rides along.
/// - extension-rows: row Actions and colored symbol rows in the panel.
/// - catalog: the catalog list, detail and filter inside the panel.
/// - herdr: question cards clicked at fixed offsets from the panel height, machine rows and the footer.
/// - rex: Rex pane rows and the footer status drawn in the panel.
/// - clipboard-recovery, spotlight-recovery: error, progress and Retry states drawn in the panel.
/// Default size only, because they draw standalone windows that ignore the launcher size:
/// - community-settings, extension-settings: Extension Settings states and the location prompt.
/// - dictation-vocabulary: Dictation Settings with a vocabulary, and the word editor.
/// - api-settings, acp-detection, acp-resume, acp-several, acp-accounts: AI Settings and the
///   standalone chat view and activity strip.
/// - notes-recovery: the notes panel, which has its own size.
/// - rex-overview: the Rex Overview window, which has its own size.
/// Listening servers from compiled release assets: runtime logos in brand color, the generic tile
/// for a runtime without a logo and for other processes, and the row's Actions. Every server is fictional.
func serversScenario() throws {
    let started = Date().addingTimeInterval(-7200)
    panel.model.servers.loadOverride = { $0([
        ListeningServer(pid: 4101, port: 3000, process: "node", executable: "/opt/fictional/bin/node", directory: "/Users/fictional/site", exposed: false, started: started),
        ListeningServer(pid: 4102, port: 8000, process: "python3.12", executable: "/opt/fictional/bin/python3.12", directory: "/Users/fictional/api", exposed: true, started: started),
        ListeningServer(pid: 4105, port: 6379, process: "redis-server", executable: "/opt/fictional/bin/redis-server", directory: nil, exposed: false, started: started),
        ListeningServer(pid: 4106, port: 5432, process: "postgres", executable: "/opt/fictional/bin/postgres", directory: nil, exposed: false, started: started),
        ListeningServer(pid: 4107, port: 8080, process: "java", executable: "/opt/fictional/jdk/bin/java", directory: "/Users/fictional/service", exposed: false, started: started),
        ListeningServer(pid: 4103, port: 6463, process: "Fictional Chat", executable: "/Applications/Fictional Chat.app/Contents/MacOS/Fictional Chat", directory: nil, exposed: false),
    ], nil) }
    summon()
    panel.model.query = "servers"; settle()
    verify(waitUntil { panel.model.rows.count == 6 }, "Servers shows the fictional listeners: \(panel.model.rows.map(\.id))")
    for asset in ["nodedotjs", "python", "redis", "postgresql"] {
        verify(NSImage(named: "Runtimes/" + asset) != nil, "Runtime logo \(asset) is in the compiled catalog")
    }
    try render("servers")
    key("k", 40, .command)
    verify(waitUntil { panel.model.actionTarget != nil }, "Command K opens a server's Actions")
    verify(panel.model.actionTarget?.menuEntries == [.item(.open), .item(.reveal), .item(.copyURL), .item(.copyPort), .item(.copyPID)],
           "A server offers Open, Reveal and the three copies")
    verify(panel.model.actionTarget?.commandReturnEntry == .item(.copyURL), "Command-Return in a server's Actions copies the URL, as it does from the results")
    try render("servers-actions")
    copied = []
    focusActionSearch(); key("\r", 36, .command)
    verify(copied == ["http://localhost:3000"], "Command-Return in the menu copies the URL: \(copied)")
}

let scenarios: [Scenario] = [
    Scenario(name: "actions", sizeSensitive: true, run: actionsMenuScenario),
    Scenario(name: "volant-menu", sizeSensitive: true, run: volantMenuScenario),
    Scenario(name: "panel-chat", sizeSensitive: true, run: panelChatScenario),
    Scenario(name: "community-launcher", sizeSensitive: true, run: communityLauncherScenario),
    Scenario(name: "community-settings", sizeSensitive: false, run: communitySettingsScenario),
    Scenario(name: "extension-rows", sizeSensitive: true, run: extensionRowsScenario),
    Scenario(name: "extension-settings", sizeSensitive: false, run: extensionSettingsScenario),
    Scenario(name: "dictation-vocabulary", sizeSensitive: false, run: dictationVocabularyScenario),
    Scenario(name: "catalog", sizeSensitive: true, run: catalogScenario),
    Scenario(name: "herdr", sizeSensitive: true, run: herdrScenario),
    Scenario(name: "rex", sizeSensitive: true, run: rexScenario),
    Scenario(name: "servers", sizeSensitive: true, run: serversScenario),
    Scenario(name: "rex-overview", sizeSensitive: false, run: rexOverviewScenario),
    Scenario(name: "api-settings", sizeSensitive: false, run: apiSettingsScenario),
    Scenario(name: "acp-detection", sizeSensitive: false, run: acpDetectionScenario),
    Scenario(name: "acp-resume", sizeSensitive: false, run: acpResumeScenario),
    Scenario(name: "acp-several", sizeSensitive: false, run: acpSeveralScenario),
    Scenario(name: "acp-accounts", sizeSensitive: false, run: acpAccountsScenario),
    Scenario(name: "clipboard-recovery", sizeSensitive: true, run: clipboardRecoveryScenario),
    Scenario(name: "spotlight-recovery", sizeSensitive: true, run: spotlightRecoveryScenario),
    Scenario(name: "notes-recovery", sizeSensitive: false, run: notesRecoveryScenario),
]

app.activate(ignoringOtherApps: true)
for scenario in scenarios where (defaultScale || scenario.sizeSensitive) && (language == nil || scenario.name == "servers") {
    currentScenario = scenario.name
    freshLauncher()
    try scenario.run()
    panel.orderOut(nil)
}
