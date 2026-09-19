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
var extensionSettingsRequests = 0
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
    case .extensionSettings: extensionSettingsRequests += 1; panel.orderOut(nil)
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
panel.toggle(); settle(); key("\t", 48)
verify(settingsRequests == 1 && !panel.isVisible, "Unconfigured AI Chat routes to Settings")
chatConfig = AIConfiguration(); chatConfig?.provider = "claude"
panel.toggle(); settle()
(panel.firstResponder as? NSTextView)?.insertText("A fictional question", replacementRange: NSRange(location: NSNotFound, length: 0)); settle()
key("\t", 48)
verify(panel.model.acp.draft == "A fictional question" && !panel.model.acp.submitting, "Tab carries search text to an unsent chat draft")
panel.model.acp.draft = ""; settle()
verify(panel.model.acp.state.phase == "ready" && panel.model.acp.project.isEmpty, "Configured AI Chat automatically connects without a project")
verify(panel.firstResponder is NSTextView, "Chat prompt receives focus")
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
let savedMessages = panel.model.acp.state.messages
let savedDraft = panel.model.acp.draft
panel.orderOut(nil); settle(); panel.toggle(); settle()
verify(!panel.model.showingACP && panel.model.query.isEmpty, "Summoning a hidden chat opens the default launcher")
verify(panel.model.acp.state.messages == savedMessages && panel.model.acp.draft == savedDraft && panel.model.acp.active, "Summoning preserves the active conversation and draft")
try render("chat-home")
panel.model.config.statusBar.sources = ["ai-chat"]
settle()
try render("chat-status-pinned")
panel.model.config.statusBar.sources = []
settle()
let search = fields(panel.contentView!).first { $0.placeholderString == "Search for apps, files, contacts, or calculate…" }!
panel.makeFirstResponder(search)
(panel.firstResponder as? NSTextView)?.insertText("Do not replace my draft", replacementRange: NSRange(location: NSNotFound, length: 0)); settle()
key("\t", 48)
verify(panel.model.showingACP && panel.model.acp.draft == savedDraft, "Tab resumes chat without overwriting its draft")
// A busy chat stays visible on blur, but a subsequent summon returns to search.
panel.model.acp.state.phase = "working"
let backgroundWindow = NSWindow(contentRect: NSRect(x: 20, y: 20, width: 180, height: 100), styleMask: [.titled], backing: .buffered, defer: false)
backgroundWindow.makeKeyAndOrderFront(nil); settle()
verify(panel.isVisible && !panel.isKeyWindow && panel.model.showingACP, "Working chat remains visible on real focus loss")
panel.toggle(); settle()
verify(!panel.model.showingACP && panel.model.query.isEmpty && panel.model.acp.state.phase == "working", "Summoning a visible inactive chat returns home without stopping the turn")
verify(panel.model.acp.state.messages == savedMessages && panel.model.acp.draft == savedDraft, "Focus loss and summon preserve conversation state")
key("\t", 48)
verify(panel.model.showingACP, "Tab resumes the working conversation")
backgroundWindow.orderOut(nil)
panel.model.acp.state.phase = "ready"
(panel.firstResponder as? NSTextView)?.insertText("!", replacementRange: NSRange(location: NSNotFound, length: 0)); settle()
verify(panel.model.acp.draft.contains("!") && panel.model.query == "ai", "Resuming chat restores native prompt focus")
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

// Bundled extensions are discoverable but never run before explicit consent.
panel.toggle()
panel.model.query = "hello Andrew"
settle()
verify(panel.model.rows.first?.primaryAction == "Enable and Run…", "Hello World starts disabled")
verify(!panel.model.extensionRunning && panel.model.pendingExtension == nil, "Typing an extension name never executes or enables it")
try render("direct-extension-launcher")
panel.model.query = "hello world Andrew"; settle()
verify(panel.model.rows.contains { if case .extensionRun(_, let input) = $0 { return input == "Andrew" }; return false }, "Full display name separates arguments")
panel.model.query = "ext hello Andrew"; settle()
verify(panel.model.rows.first?.primaryAction == "Enable and Run…", "Legacy ext prefix remains supported")
panel.model.query = "hello Andrew"; settle()

key("\r", 36)
verify(panel.model.pendingExtension?.input == "Andrew", "First invocation requests consent without executing")
verify(panel.keepsVisibleOnBlur, "Extension consent keeps its parent panel visible")
let permission = panel.model.pendingExtension!
let consentView = NSHostingView(rootView: ExtensionPermissionView(request: permission, enable: {}, cancel: {}))
consentView.frame = NSRect(x: 0, y: 0, width: 438, height: 240)
try render("extension-consent", view: consentView)
panel.model.pendingExtension = nil
settle()
panel.orderOut(nil)
settings.state.section = "Extensions"
settings.showWindow(nil); settle()
try render("extension-settings", view: settings.window!.contentView!)
settings.window!.orderOut(nil)

// The master gate applies to installed community code, never a manifest's claimed origin/ID.
let bundledExtension = Bundle.main.url(forResource: "HelloWorld", withExtension: nil)!
let communityDirectory = root.appendingPathComponent("community-example-" + UUID().uuidString)
try FileManager.default.copyItem(at: bundledExtension, to: communityDirectory)
let communityManifestURL = communityDirectory.appendingPathComponent("manifest.json")
var communityManifest = try JSONDecoder().decode(ExtensionManifest.self, from: Data(contentsOf: communityManifestURL))
communityManifest.id = "fixture.community"; communityManifest.name = "Community Greeting"
try JSONEncoder().encode(communityManifest).write(to: communityManifestURL)
let extensionRoots = [bundledExtension, communityDirectory]
let communityManager = ExtensionManager(configURL: panel.model.actionConfigURL, roots: extensionRoots)
communityManager.reload()
verify(!communityManager.communityAllowed, "Community extensions default off")
verify(!communityManager.extensions.first(where: { !$0.isCommunity })!.communityBlocked, "Bundled example is independent of master gate")
panel.model.extensions = communityManager
communityManifest.name = "Fixture"
try JSONEncoder().encode(communityManifest).write(to: communityManifestURL)
communityManager.reload()
panel.model.query = "Fixture"; settle()
verify(panel.model.rows.contains { if case .app = $0 { return true }; return false }, "An extension name cannot hide a matching application")
verify(panel.model.rows.contains { if case .extensionRun = $0 { return true }; return false }, "Extension and app name collisions remain selectable")
communityManifest.name = "Community Greeting"
try JSONEncoder().encode(communityManifest).write(to: communityManifestURL)
communityManager.reload()

panel.model.query = "community"; settle()
verify(panel.model.rows.contains { if case .extensionRun = $0 { return true }; return false }, "Direct search discovers master-blocked commands without execution")

panel.toggle(); panel.model.query = "community Andrew"; settle()
verify(panel.model.rows.first?.primaryAction == "Open Extension Settings", "Blocked community command points to Settings")
try render("community-blocked-launcher")
key("\r", 36)
verify(extensionSettingsRequests == 1 && panel.model.pendingExtension == nil, "Master off routes to Settings without offering enable or executing")
func renderCommunitySettings(_ name: String) throws {
    let view = NSHostingView(rootView: ExtensionSettingsView(configURL: panel.model.actionConfigURL, onChange: {}, roots: extensionRoots)
        .padding(16).background(Color(nsColor: .windowBackgroundColor)))
    let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 460, height: 440), styleMask: [.titled], backing: .buffered, defer: false)
    window.contentView = view; window.makeKeyAndOrderFront(nil); settle()
    try render(name, view: view)
    window.orderOut(nil)
}
try renderCommunitySettings("community-off")
try communityManager.setCommunityAllowed(true, expected: false)
panel.toggle(); panel.model.query = "community Andrew"; settle()
verify(panel.model.rows.first?.primaryAction == "Enable and Run…", "Allowing community code still requires individual consent")
try render("community-first-use-launcher")
key("\r", 36)
verify(panel.model.pendingExtension?.extensionItem.id == "fixture.community", "Community first use requests per-extension consent")
try communityManager.setCommunityAllowed(false, expected: true)
panel.model.enablePendingExtension()
verify(!panel.model.extensionRunning && !ExtensionApproval.enabled(communityManifest, at: panel.model.actionConfigURL), "Stale consent cannot bypass revoked master gate")
panel.orderOut(nil)
try communityManager.setCommunityAllowed(true, expected: false)
try communityManager.setEnabled(communityManager.search("community").first!, true)
try renderCommunitySettings("community-on")
try communityManager.setCommunityAllowed(false, expected: true)
try renderCommunitySettings("community-paused")
print("PASS: community master default, Settings routing, individual consent, stale consent rejection and retained individual choices")
panel.model.query = ""

// Local panes remain visible while remote machines are still loading.
panel.model.agents.connected = true
panel.model.agents.busy = true
panel.model.agents.sessions = [AgentSession(agent: "codex", agentStatus: "working", paneID: "w1:p1", terminalID: "local-fixture", cwd: "/fictional/local-project", terminalTitle: nil, agentSession: nil)]
panel.model.agents.machines = [
    .init(id: "local", label: "Local", state: "connected", detail: "1 pane"),
    .init(id: "remote:fixture", label: "Build Mac", state: "loading", detail: "Loading panes…")
]
panel.toggle()
panel.model.query = "agents"
settle()
verify(panel.model.showingAgents && panel.model.rows.count == 1, "Local pane is usable while the remote machine loads")
try render("machines-loading")
panel.orderOut(nil)
panel.model.query = ""
panel.model.agents.busy = false

// Passive Herdr previews use fictional terminal output and no helper connection.
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
// SwiftUI starts the preview in .task after presentation. A fixed 200 ms delay
// can expire on a loaded CI runner before that task starts; wait for its effect.
let previewDeadline = Date().addingTimeInterval(3)
while (!panel.model.agents.attentionLoading || previewReply == nil) && Date() < previewDeadline {
    RunLoop.main.run(until: Date().addingTimeInterval(0.02))
}
verify(panel.model.agents.attentionLoading && previewReply != nil, "Pinned waiting agent starts a passive preview read")
try render("attention-loading")
previewReply?(try JSONEncoder().encode(HerdrResponseController.Snapshot(text: "Allow running npm test in /fictional/orbit?\n\n1. Yes, once\n2. Yes, for this session\n3. No", token: nil, question: nil)), nil); settle()
verify(panel.model.agents.attention?.text.contains("npm test") == true, "Waiting question appears below the pinned status")
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
point = NSPoint(x: 90, y: panel.contentView!.bounds.height - 272)
clickPoint()
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
point = NSPoint(x: 90, y: panel.contentView!.bounds.height - 324)
clickPoint()
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
UserDefaults.standard.set(true, forKey: "showHerdrDetails"); settle()
try render("machines-details")
UserDefaults.standard.set(false, forKey: "showHerdrDetails"); settle()
panel.orderOut(nil)
print("PASS: passive Herdr question previews, target changes, loading, error, and resolved states")

// API/local Settings use fictional discovery and credentials, never host services or owner keys.
let aiFixtureURL = root.appendingPathComponent("api-settings.json")
try Data("{}".utf8).write(to: aiFixtureURL)
var credentialWrites = 0
let fakeCredentials = AICredentials(read: { _ in nil }, write: { _, _ in credentialWrites += 1 })
func renderAPISettings(_ kind: AIConnectionKind, provider: AIAPIProvider = .openAI, offline: Bool = false) throws {
    var config = AIConfiguration(); config.connection = kind; config.api.provider = provider; config.api.endpoint = provider.endpoint
    try config.save(at: aiFixtureURL)
    let discovery = AIModelDiscovery()
    discovery.lookupOverride = { candidate, _, completion in
        if candidate.endpoint.contains("11434") && !offline { completion(["fictional-local-model", "fictional-second-model"], nil) }
        else { completion(nil, "Server unavailable. Start it or enter a custom URL.") }
    }
    let model = ACPModel()
    let view = NSHostingView(rootView: AISettingsView(model: model, configURL: aiFixtureURL, onChange: {}, openConversation: { _ in }, chooseProject: { _ in }, credentials: fakeCredentials, discovery: discovery)
        .padding(16).background(Color(nsColor: .windowBackgroundColor)))
    let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 480, height: 660), styleMask: [.titled], backing: .buffered, defer: false)
    window.contentView = view; window.makeKeyAndOrderFront(nil); settle()
    try render("ai-\(kind.rawValue)-\(provider.rawValue)\(offline ? "-offline" : "")", view: view)
    verify(!model.active && credentialWrites == 0, "Opening AI Settings never starts chat or writes credentials")
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
let apiChat = NSHostingView(rootView: ACPConversationView(model: apiModel))
apiChat.frame = NSRect(x: 0, y: 0, width: 740, height: 450)
try render("ai-local-chat", view: apiChat)
apiModel.state.phase = "disconnected"
print("PASS: BYOK/local Settings and chat fixtures use no real servers or credentials")
