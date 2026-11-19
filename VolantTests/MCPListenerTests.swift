import XCTest
import VolantCore
@testable import Volant

@MainActor
final class MCPListenerTests: XCTestCase {
    private var root: URL!
    private var socketURL: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("mcp-" + UUID().uuidString.prefix(6))
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        socketURL = root.appendingPathComponent("s")
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    private let meta: MCPValue = .object(["io.modelcontextprotocol/protocolVersion": .string("2026-07-28"),
                                          "io.modelcontextprotocol/clientCapabilities": .object([:])])

    /// A listener whose signature check reports `peer`, with one read tool.
    private func listener(peer: MCPListener.Peer?, preferences: MCPPreferences = MCPPreferences(enabled: true)) -> MCPListener {
        let listener = MCPListener(socketURL: socketURL, identify: { _ in peer }, ownTeam: "TEAM", version: "9.9")
        listener.makeTools = { _, _ in
            [MCPTool(name: "calculate", title: "Calculate", description: "", inputSchema: MCPTool.noArguments, readOnly: true) { _ in .data(.int(4)) }]
        }
        listener.apply(preferences)
        return listener
    }

    /// Connects, sends the lines, and returns every reply line until the listener closes or goes quiet.
    private func exchange(_ lines: [MCPValue]) throws -> [MCPValue] {
        let descriptor = socket(AF_UNIX, SOCK_STREAM, 0)
        defer { close(descriptor) }
        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        let path = Array(socketURL.path.utf8)
        withUnsafeMutableBytes(of: &address.sun_path) { $0.copyBytes(from: path); $0[path.count] = 0 }
        let connected = withUnsafePointer(to: &address) { $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { connect(descriptor, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) } }
        guard connected == 0 else { throw POSIXError(.ECONNREFUSED) }
        var on: Int32 = 1
        setsockopt(descriptor, SOL_SOCKET, SO_NOSIGPIPE, &on, socklen_t(MemoryLayout<Int32>.size))
        var timeout = timeval(tv_sec: 2, tv_usec: 0)
        setsockopt(descriptor, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
        let payload = lines.map { $0.line() + Data([0x0A]) }.reduce(Data(), +)
        _ = payload.withUnsafeBytes { Darwin.write(descriptor, $0.baseAddress!, payload.count) }
        Darwin.shutdown(descriptor, SHUT_WR)
        var reader = LineReader(descriptor: descriptor)
        var replies: [MCPValue] = []
        while let line = reader.next() { replies.append(try JSONDecoder().decode(MCPValue.self, from: line)) }
        return replies
    }

    private var handshake: MCPValue { .object(["volantBridge": .int(1), "client": .string("claude-code")]) }

    private func request(_ id: Int, _ method: String, _ params: [String: MCPValue] = [:]) -> MCPValue {
        var params = params
        params["_meta"] = meta
        return .object(["jsonrpc": .string("2.0"), "id": .int(id), "method": .string(method), "params": .object(params)])
    }

    func testServesTheBridgeAndNamesNewClients() throws {
        let server = listener(peer: .init(team: "TEAM", identifier: MCPEndpoint.bridgeIdentifier))
        defer { server.stop() }
        var named: [String] = []
        server.onNewClient = { named.append($0) }
        let replies = try exchange([handshake, request(1, "tools/list"), request(2, "tools/call", ["name": .string("calculate")])])
        XCTAssertEqual(replies.count, 2)
        XCTAssertEqual(replies[0]["result"]?["tools"], .array([MCPTool(name: "calculate", title: "Calculate", description: "", inputSchema: MCPTool.noArguments, readOnly: true) { _ in .data(.null) }.listingForTests]))
        XCTAssertEqual(replies[1]["result"]?["structuredContent"], .int(4))
        RunLoop.main.run(until: Date().addingTimeInterval(0.1))
        XCTAssertEqual(named, ["claude-code"])
        var mode = stat()
        XCTAssertEqual(lstat(socketURL.path, &mode), 0)
        XCTAssertEqual(mode.st_mode & 0o777, 0o600, "Only the owner's processes may open the socket")
    }

    func testRefusesAnyPeerButTheBridgeFromTheSameTeam() throws {
        for peer in [MCPListener.Peer(team: "OTHER", identifier: MCPEndpoint.bridgeIdentifier), .init(team: "TEAM", identifier: "com.example.tool"),
                     .init(team: nil, identifier: MCPEndpoint.bridgeIdentifier)] as [MCPListener.Peer?] + [nil] {
            let server = listener(peer: peer)
            XCTAssertEqual(try exchange([handshake, request(1, "tools/list")]), [], "\(String(describing: peer))")
            server.stop()
        }
        let unsigned = MCPListener(socketURL: socketURL, identify: { _ in .init(team: nil, identifier: nil) }, ownTeam: nil)
        unsigned.apply(MCPPreferences(enabled: true))
        XCTAssertEqual(try exchange([handshake, request(1, "tools/list")]), [], "An unsigned Volant serves no one")
        unsigned.stop()
    }

    func testBadHandshakeClosesTheConnection() throws {
        let server = listener(peer: .init(team: "TEAM", identifier: MCPEndpoint.bridgeIdentifier))
        defer { server.stop() }
        XCTAssertEqual(try exchange([request(1, "tools/list")]), [], "The first line must be the handshake")
        XCTAssertEqual(try exchange([.object(["volantBridge": .int(1), "client": .string("bad name")]), request(1, "tools/list")]), [])
    }

    func testDisconnectedAppsAreRefusedAndTurningOffStopsListening() throws {
        let server = listener(peer: .init(team: "TEAM", identifier: MCPEndpoint.bridgeIdentifier),
                              preferences: MCPPreferences(enabled: true, disconnectedClients: ["claude-code"]))
        let replies = try exchange([handshake, request(1, "tools/list")])
        XCTAssertEqual(replies.first?["error"]?["code"], .int(-31002))
        server.apply(MCPPreferences())
        XCTAssertFalse(server.isListening)
        XCTAssertFalse(FileManager.default.fileExists(atPath: socketURL.path), "Turning the server off removes the socket")
        XCTAssertThrowsError(try exchange([handshake]))
    }
}

@MainActor
final class MCPToolboxTests: XCTestCase {
    private var root: URL!
    private var configURL: URL!
    private var notes: NotesStore!
    private var reloads = 0

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root.appendingPathComponent("Notes"), withIntermediateDirectories: true)
        configURL = root.appendingPathComponent("config.json")
        try Data(#"{"snippets":[{"name":"Address","keyword":"addr","body":"1 Main St"}],"quicklinks":[],"future":1}"#.utf8).write(to: configURL)
        notes = NotesStore(directory: root.appendingPathComponent("Notes"))
    }

    override func tearDownWithError() throws {
        notes.flush()
        try? FileManager.default.removeItem(at: root)
    }

    private func toolbox() -> MCPToolbox {
        MCPToolbox(notes: notes, configURL: configURL, breakHistoryURL: root.appendingPathComponent("break-history.json"),
                   breakStatus: { (true, "Next break in 12 min · active time") }, focusStatus: { ("Ship MCP", false, "12:00") },
                   configChanged: { [unowned self] in self.reloads += 1 })
    }

    private func call(_ name: String, _ arguments: [String: MCPValue] = [:], writes: Bool = true) async -> MCPToolResult? {
        let preferences = MCPPreferences(enabled: true, writesNotes: writes, writesSnippets: writes, writesQuicklinks: writes)
        guard let tool = toolbox().tools(preferences).first(where: { $0.name == name }) else { return nil }
        return await tool.call(arguments)
    }

    func testWriteToolsAppearOnlyWithTheirSwitch() {
        let names = { (preferences: MCPPreferences) in self.toolbox().tools(preferences).map(\.name) }
        XCTAssertEqual(names(MCPPreferences(enabled: true)), ["calculate", "search_notes", "read_note", "list_snippets", "list_quicklinks", "break_status", "focus_status"])
        XCTAssertEqual(names(MCPPreferences(enabled: true, writesSnippets: true)).last, "add_snippet")
        XCTAssertTrue(toolbox().tools(MCPPreferences(enabled: true)).allSatisfy(\.readOnly))
        XCTAssertTrue(toolbox().tools(MCPPreferences(enabled: true, writesNotes: true, writesSnippets: true, writesQuicklinks: true)).filter { !$0.readOnly }
            .allSatisfy { !$0.destructive }, "Phase 1 writes only add")
    }

    func testCalculateAndStatus() async {
        let sum = await call("calculate", ["query": .string("2+2")])
        XCTAssertEqual(sum?.isError, false)
        XCTAssertEqual(sum?.structured?["answers"]?.firstForTests?["result"], .string("4"))
        let nonsense = await call("calculate", ["query": .string("zzqq")])
        XCTAssertEqual(nonsense?.isError, true)
        let focus = await call("focus_status")
        XCTAssertEqual(focus?.structured?["goal"], .string("Ship MCP"))
        let breaks = await call("break_status")
        XCTAssertEqual(breaks?.structured?["enabled"], .bool(true))
        XCTAssertEqual(breaks?.structured?["today"]?["breaks"], .int(0))
    }

    func testNotesCreateAppendSearchAndRead() async {
        let created = await call("create_note", ["text": .string("# Groceries\nmilk")])
        guard let id = created?.structured?["id"]?.string else { return XCTFail("no id") }
        XCTAssertEqual(created?.structured?["title"], .string("Groceries"))
        let appended = await call("append_to_note", ["id": .string(id), "text": .string("eggs")])
        XCTAssertEqual(appended?.isError, false)
        let read = await call("read_note", ["id": .string(id)])
        XCTAssertEqual(read?.structured?["text"], .string("# Groceries\nmilk\neggs"))
        XCTAssertNil(read?.structured?["nextOffset"])
        let found = await call("search_notes", ["query": .string("Groceries")])
        XCTAssertEqual(found?.structured?["notes"]?.arrayCountForTests, 1)
        let missing = await call("read_note", ["id": .string("nope.md")])
        XCTAssertEqual(missing?.isError, true)
        let off = await call("create_note", ["text": .string("x")], writes: false)
        XCTAssertNil(off, "Without the switch the tool isn't offered at all")
    }

    func testSnippetsAndQuicklinksGoThroughLauncherEntries() async throws {
        let list = await call("list_snippets")
        XCTAssertEqual(list?.structured?["snippets"], .array([.object(["name": .string("Address"), "keyword": .string("addr"), "text": .string("1 Main St")])]))
        let added = await call("add_snippet", ["name": .string("Shell"), "keyword": .string("lsa"), "text": .string("ls -la")])
        XCTAssertEqual(added?.isError, false)
        let duplicate = await call("add_snippet", ["name": .string("Address"), "text": .string("2 Main St")])
        XCTAssertEqual(duplicate?.isError, true)
        let reserved = await call("add_quicklink", ["name": .string("notes"), "url": .string("https://example.com")])
        XCTAssertEqual(reserved?.isError, true, "Built-in command words are refused, as in the launcher form")
        let badScheme = await call("add_quicklink", ["name": .string("Run"), "url": .string("file:///etc/passwd")])
        XCTAssertEqual(badScheme?.isError, true)
        let link = await call("add_quicklink", ["name": .string("Linear"), "url": .string("https://linear.app/search?q={query}")])
        XCTAssertEqual(link?.isError, false)
        let saved = try JSONDecoder().decode(Preferences.self, from: Data(contentsOf: configURL))
        XCTAssertEqual(saved.snippets.map(\.name), ["Address", "Shell"])
        XCTAssertEqual(saved.quicklinks.map(\.name), ["Linear"])
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: configURL)) as? [String: Any])
        XCTAssertEqual(object["future"] as? Int, 1, "Unknown keys survive")
        XCTAssertEqual(reloads, 2)
    }
}

@MainActor
final class MCPToolboxPhaseTwoTests: XCTestCase {
    private var root: URL!
    private var notes: NotesStore!
    private var focusRequests: [MCPToolbox.FocusControl] = []
    private var breakRequests: [MCPToolbox.BreakControl] = []

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root.appendingPathComponent("Notes"), withIntermediateDirectories: true)
        try Data(#"{"snippets":[{"name":"Address","keyword":"addr","body":"1 Main St"}],"quicklinks":[]}"#.utf8).write(to: root.appendingPathComponent("config.json"))
        notes = NotesStore(directory: root.appendingPathComponent("Notes"))
    }

    override func tearDownWithError() throws {
        notes.flush()
        try? FileManager.default.removeItem(at: root)
    }

    private func toolbox() -> MCPToolbox {
        MCPToolbox(notes: notes, configURL: root.appendingPathComponent("config.json"), breakHistoryURL: root.appendingPathComponent("h.json"),
                   breakStatus: { (true, "Next break in 3 min · active time") }, focusStatus: { ("Write", false, "24:00") },
                   focusControl: { [unowned self] control in
                       self.focusRequests.append(control)
                       return control == .resume ? "No Focus session is paused." : nil
                   },
                   breakControl: { [unowned self] control in self.breakRequests.append(control); return nil })
    }

    func testControlsAppearOnlyWithTheirSwitches() {
        let names = toolbox().tools(MCPPreferences(enabled: true, controlsFocus: true, controlsBreaks: true)).map(\.name)
        XCTAssertTrue(names.contains("start_focus") && names.contains("take_break") && names.contains("resume_breaks"))
        XCTAssertFalse(toolbox().tools(MCPPreferences(enabled: true)).map(\.name).contains("start_focus"))
        XCTAssertFalse(toolbox().tools(MCPPreferences(enabled: true, controlsFocus: true)).map(\.name).contains("take_break"))
    }

    private func call(_ name: String, _ arguments: [String: MCPValue] = [:]) async -> MCPToolResult? {
        let tool = toolbox().tools(MCPPreferences(enabled: true, controlsFocus: true, controlsBreaks: true)).first { $0.name == name }
        return await tool?.call(arguments)
    }

    func testFocusAndBreakControlsRunThroughTheControllers() async {
        let started = await call("start_focus", ["goal": .string("Ship phase 2"), "minutes": .int(45)])
        XCTAssertEqual(started?.isError, false)
        XCTAssertEqual(started?.structured?["goal"], .string("Write"), "The reply is the state after the change")
        XCTAssertEqual(focusRequests, [.start(goal: "Ship phase 2", minutes: 45)])
        let tooLong = await call("start_focus", ["minutes": .int(FocusSetup.maximumMinutes + 1)])
        XCTAssertEqual(tooLong?.isError, true)
        XCTAssertEqual(focusRequests.count, 1, "An invalid length never reaches Focus")
        let refused = await call("resume_focus")
        XCTAssertEqual(refused?.isError, true)
        XCTAssertEqual(refused?.text, "No Focus session is paused.")
        _ = await call("take_break")
        _ = await call("pause_breaks")
        XCTAssertEqual(breakRequests, [.takeNow, .pauseHour])
    }

    private final class ControlOwner {
        var requests: [MCPToolbox.FocusControl] = []
        var problem: String?

        @MainActor func control(_ control: MCPToolbox.FocusControl) -> String? {
            requests.append(control)
            return problem
        }
    }

    /// A control that succeeds returns nil; relaying it through a live owner must stay a success,
    /// which `owner?.control(c) ?? "unavailable"` turned into a failure after starting Focus.
    @MainActor func testRelayReportsUnavailableOnlyWhenTheOwnerIsGone() async {
        let owner = ControlOwner()
        let relayed: @MainActor (MCPToolbox.FocusControl) -> String? = { [weak owner] control in
            MCPToolbox.relay(owner, control, unavailable: "Focus isn't available.") { $0.control($1) }
        }
        XCTAssertNil(relayed(.start(goal: "Test", minutes: 5)))
        owner.problem = "No Focus session is paused."
        XCTAssertEqual(relayed(.resume), "No Focus session is paused.")
        XCTAssertEqual(owner.requests, [.start(goal: "Test", minutes: 5), .resume])
        XCTAssertEqual(MCPToolbox.relay(nil as ControlOwner?, .end, unavailable: "Focus isn't available.") { $0.control($1) },
                       "Focus isn't available.")

        owner.problem = nil
        let box = MCPToolbox(notes: notes, configURL: root.appendingPathComponent("config.json"), breakHistoryURL: root.appendingPathComponent("h.json"),
                             focusStatus: { ("Test", false, "5:00") }, focusControl: relayed)
        let started = await box.tools(MCPPreferences(enabled: true, controlsFocus: true)).first { $0.name == "start_focus" }?
            .call(["goal": .string("Test"), "minutes": .int(5)])
        XCTAssertEqual(started?.isError, false, "A Focus session that started is reported as started")
        XCTAssertEqual(started?.structured?["active"], .bool(true))
    }

    func testResourcesListPagesAndReadNotesSnippetsAndQuicklinks() async throws {
        let note = notes.create(initialText: "# Plan\nphase 2")
        let resources = toolbox().resources()
        let first = await resources.list(nil)
        XCTAssertEqual(first.resources.compactMap { $0["uri"]?.string }, ["volant://snippets", "volant://quicklinks", MCPToolbox.noteURI(note.id)])
        XCTAssertNil(first.nextCursor)
        let snippets = await resources.read("volant://snippets")
        XCTAssertEqual(snippets?.first?["text"], .string(#"[{"keyword":"addr","name":"Address","text":"1 Main St"}]"#))
        let read = await resources.read(MCPToolbox.noteURI(note.id))
        XCTAssertEqual(read?.first?["text"], .string("# Plan\nphase 2"))
        XCTAssertEqual(read?.first?["mimeType"], .string("text/markdown"))
        let traversal = await resources.read("volant://notes/..%2F..%2Fconfig.json")
        XCTAssertNil(traversal, "Only ids in the notes list resolve; nothing builds a path")
        let unknown = await resources.read("volant://notes/missing.md")
        XCTAssertNil(unknown)
        for index in 0..<60 { notes.create(initialText: "# Note \(index)") }
        let paged = await resources.list(nil)
        XCTAssertEqual(paged.resources.count, MCPToolbox.resourcePage)
        let next = await resources.list(paged.nextCursor)
        XCTAssertEqual(next.resources.count, 63 - MCPToolbox.resourcePage)
        XCTAssertNil(next.nextCursor)
    }
}

extension MCPTool {
    /// The listing `tools/list` sends, for comparing in tests.
    var listingForTests: MCPValue {
        .object(["name": .string(name), "title": .string(title), "description": .string(description), "inputSchema": inputSchema,
                 "annotations": .object(["title": .string(title), "readOnlyHint": .bool(readOnly), "destructiveHint": .bool(destructive),
                                         "idempotentHint": .bool(idempotent), "openWorldHint": .bool(false)])])
    }
}

extension MCPValue {
    var arrayCountForTests: Int? { if case .array(let items) = self { return items.count } else { return nil } }
    var firstForTests: MCPValue? { if case .array(let items) = self { return items.first } else { return nil } }
}
