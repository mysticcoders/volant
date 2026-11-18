import XCTest

@testable import VolantCore

final class MCPSessionTests: XCTestCase {
    private var now = Date(timeIntervalSince1970: 1_800_000_000)
    private var refusal: MCPRefusal?
    private var calls: [[String: MCPValue]] = []

    private let modernMeta: MCPValue = .object(["io.modelcontextprotocol/protocolVersion": .string("2026-07-28"),
                                                "io.modelcontextprotocol/clientCapabilities": .object([:])])

    /// A session with one read tool that echoes its `text` argument and one that fails.
    private func session() -> MCPSession {
        let echo = MCPTool(name: "echo", title: "Echo", description: "Echoes text.",
                           inputSchema: MCPTool.schema(["text": MCPTool.string("Text to echo.")], required: ["text"]), readOnly: true) { [unowned self] arguments in
            self.calls.append(arguments)
            return .data(.object(["echo": arguments["text"] ?? .null]))
        }
        let broken = MCPTool(name: "broken", title: "Broken", description: "Always fails.", inputSchema: MCPTool.noArguments, readOnly: false) { _ in
            .failure("That didn't work; try a shorter note.")
        }
        return MCPSession(version: "0.4.4", instructions: "Volant's notes and tools.", tools: { [echo, broken] },
                          refusal: { [unowned self] in self.refusal }, clock: { [unowned self] in self.now })
    }

    /// Sends one message and decodes the reply.
    private func send(_ session: MCPSession, _ message: MCPValue) async throws -> MCPValue? {
        guard let reply = await session.handle(message.line()) else { return nil }
        XCTAssertFalse(reply.contains(0x0A), "Replies are single lines")
        return try JSONDecoder().decode(MCPValue.self, from: reply)
    }

    /// Sends one message and returns its error code, if any.
    private func code(_ session: MCPSession, _ message: MCPValue) async throws -> MCPValue? {
        try await send(session, message)?["error"]?["code"]
    }

    /// Sends raw bytes and decodes the reply.
    private func raw(_ session: MCPSession, _ data: Data) async throws -> MCPValue? {
        guard let reply = await session.handle(data) else { return nil }
        return try JSONDecoder().decode(MCPValue.self, from: reply)
    }

    private func request(_ id: MCPValue, _ method: String, _ params: [String: MCPValue] = [:], modern: Bool = true) -> MCPValue {
        var params = params
        if modern { params["_meta"] = modernMeta }
        return .object(["jsonrpc": .string("2.0"), "id": id, "method": .string(method), "params": .object(params)])
    }

    func testModernDiscoverListAndCall() async throws {
        let session = session()
        let discover = try await send(session, request(.string("d1"), "server/discover"))
        XCTAssertEqual(discover?["id"], .string("d1"))
        XCTAssertEqual(discover?["result"]?["supportedVersions"], .array([.string("2026-07-28")]))
        XCTAssertEqual(discover?["result"]?["resultType"], .string("complete"))
        XCTAssertEqual(discover?["result"]?["_meta"]?["io.modelcontextprotocol/serverInfo"]?["name"], .string("Volant"))

        let list = try await send(session, request(.int(1), "tools/list"))
        XCTAssertEqual(list?["id"], .int(1), "Integer ids come back as integers")
        guard case .array(let tools)? = list?["result"]?["tools"] else { return XCTFail("no tools") }
        XCTAssertEqual(tools.map { $0["name"] }, [.string("echo"), .string("broken")])
        XCTAssertEqual(tools[0]["annotations"]?["readOnlyHint"], .bool(true))
        XCTAssertEqual(tools[1]["inputSchema"], MCPTool.noArguments)

        let call = try await send(session, request(.int(2), "tools/call", ["name": .string("echo"), "arguments": .object(["text": .string("hi")])]))
        XCTAssertEqual(call?["result"]?["isError"], .bool(false))
        XCTAssertEqual(call?["result"]?["structuredContent"], .object(["echo": .string("hi")]))
        XCTAssertEqual(call?["result"]?["content"], .array([.object(["type": .string("text"), "text": .string(#"{"echo":"hi"}"#)])]))
    }

    func testLegacyInitializeThenPlainRequests() async throws {
        let session = session()
        let initialize = try await send(session, .object(["jsonrpc": .string("2.0"), "id": .int(0), "method": .string("initialize"),
                                                         "params": .object(["protocolVersion": .string("2025-06-18"), "capabilities": .object([:]),
                                                                            "clientInfo": .object(["name": .string("claude-code"), "version": .string("1")])])]))
        XCTAssertEqual(initialize?["result"]?["protocolVersion"], .string("2025-06-18"))
        XCTAssertEqual(initialize?["result"]?["serverInfo"]?["name"], .string("Volant"))
        XCTAssertEqual(initialize?["result"]?["capabilities"]?["tools"], .object(["listChanged": .bool(false)]))
        let initialized = try await send(session, .object(["jsonrpc": .string("2.0"), "method": .string("notifications/initialized")]))
        XCTAssertNil(initialized, "Notifications get no reply")
        let list = try await send(session, request(.int(1), "tools/list", modern: false))
        XCTAssertNotNil(list?["result"]?["tools"])
        XCTAssertNil(list?["result"]?["_meta"], "Legacy results don't carry modern metadata")

        let unknownVersion = try await send(MCPSession(version: "1", instructions: "", tools: { [] }),
                                            .object(["jsonrpc": .string("2.0"), "id": .int(0), "method": .string("initialize"),
                                                     "params": .object(["protocolVersion": .string("2099-01-01")])]))
        XCTAssertEqual(unknownVersion?["result"]?["protocolVersion"], .string("2025-11-25"), "An unknown legacy version gets the newest legacy one")
    }

    func testProtocolErrors() async throws {
        let session = session()
        let noMeta = try await send(session, request(.int(1), "tools/list", modern: false))
        XCTAssertEqual(noMeta?["error"]?["code"], .int(-32602))
        let missingCapabilities = try await send(session, .object(["jsonrpc": .string("2.0"), "id": .int(2), "method": .string("tools/list"),
            "params": .object(["_meta": .object(["io.modelcontextprotocol/protocolVersion": .string("2026-07-28")])])]))
        XCTAssertEqual(missingCapabilities?["error"]?["code"], .int(-32602))
        let unsupported = try await send(session, .object(["jsonrpc": .string("2.0"), "id": .int(3), "method": .string("tools/list"),
            "params": .object(["_meta": .object(["io.modelcontextprotocol/protocolVersion": .string("1900-01-01"),
                                                 "io.modelcontextprotocol/clientCapabilities": .object([:])])])]))
        XCTAssertEqual(unsupported?["error"]?["code"], .int(-32022))
        XCTAssertEqual(unsupported?["error"]?["data"]?["requested"], .string("1900-01-01"))
        let unknownMethod = try await code(session, request(.int(4), "resources/list"))
        XCTAssertEqual(unknownMethod, .int(-32601))
        let unknownTool = try await code(session, request(.int(5), "tools/call", ["name": .string("nope")]))
        XCTAssertEqual(unknownTool, .int(-32602))
        let badArguments = try await code(session, request(.int(6), "tools/call", ["name": .string("echo"), "arguments": .string("x")]))
        XCTAssertEqual(badArguments, .int(-32602))
        let badId = try await code(session, .object(["jsonrpc": .string("2.0"), "id": .bool(true), "method": .string("ping")]))
        XCTAssertEqual(badId, .int(-32600))
        let noVersion = try await code(session, .object(["id": .int(7), "method": .string("ping")]))
        XCTAssertEqual(noVersion, .int(-32600))
        let garbage = try await raw(session, Data("{not json".utf8))
        XCTAssertEqual(garbage?["error"]?["code"], .int(-32700))
        XCTAssertEqual(garbage?["id"], .null)
        let huge = try await raw(session, Data(repeating: 0x20, count: MCPSession.maximumLineBytes + 1))
        XCTAssertEqual(huge?["error"]?["code"], .int(-32700))
        let response = try await send(session, .object(["jsonrpc": .string("2.0"), "id": .int(8), "result": .object([:])]))
        XCTAssertNil(response, "A stray response from the client is ignored")
    }

    func testToolFailuresAreResultsTheModelCanUse() async throws {
        let reply = try await send(session(), request(.int(1), "tools/call", ["name": .string("broken")]))
        XCTAssertNil(reply?["error"])
        XCTAssertEqual(reply?["result"]?["isError"], .bool(true))
        XCTAssertEqual(reply?["result"]?["content"], .array([.object(["type": .string("text"), "text": .string("That didn't work; try a shorter note.")])]))
    }

    func testRefusalsApplyToEveryRequestIncludingInitialize() async throws {
        let session = session()
        refusal = .serverOff
        let initialize = try await send(session, .object(["jsonrpc": .string("2.0"), "id": .int(0), "method": .string("initialize"), "params": .object([:])]))
        XCTAssertEqual(initialize?["error"]?["code"], .int(-31001))
        refusal = .disconnected
        let call = try await send(session, request(.int(1), "tools/call", ["name": .string("echo"), "arguments": .object(["text": .string("x")])]))
        XCTAssertEqual(call?["error"]?["code"], .int(-31002))
        XCTAssertTrue(calls.isEmpty, "A refused connection runs no tool")
        refusal = nil
        let allowed = try await send(session, request(.int(2), "tools/list"))
        XCTAssertNotNil(allowed?["result"])
    }

    func testToolCallsAreRateLimitedPerConnection() async throws {
        let session = session()
        let call = request(.int(1), "tools/call", ["name": .string("echo"), "arguments": .object(["text": .string("x")])])
        for _ in 0..<MCPSession.rateLimit { _ = try await send(session, call) }
        let limited = try await send(session, call)
        XCTAssertEqual(limited?["result"]?["isError"], .bool(true))
        XCTAssertEqual(calls.count, MCPSession.rateLimit)
        now += MCPSession.rateWindow
        let afterWindow = try await send(session, call)
        XCTAssertEqual(afterWindow?["result"]?["isError"], .bool(false))
    }

    func testEndpointNames() {
        XCTAssertEqual(MCPEndpoint.socketName(appBundleID: "com.mysticcoders.volant"), "mcp")
        XCTAssertEqual(MCPEndpoint.socketName(appBundleID: "com.mysticcoders.volant.dev"), "mcp-dev")
        XCTAssertEqual(MCPEndpoint.clientName("Claude-Code"), "claude-code")
        XCTAssertNil(MCPEndpoint.clientName(""))
        XCTAssertNil(MCPEndpoint.clientName("claude code"))
        XCTAssertNil(MCPEndpoint.clientName("é"))
        XCTAssertNil(MCPEndpoint.clientName(String(repeating: "a", count: 41)))
    }
}

final class MCPResourceSessionTests: XCTestCase {
    private let meta: MCPValue = .object(["io.modelcontextprotocol/protocolVersion": .string("2026-07-28"),
                                          "io.modelcontextprotocol/clientCapabilities": .object([:])])

    private func session(sharing: Bool = true) -> MCPSession {
        let resources = MCPResources(list: { cursor in
            cursor == nil ? ([.object(["uri": .string("volant://snippets"), "name": .string("snippets")])], "page-2")
                          : ([.object(["uri": .string("volant://notes/a.md"), "name": .string("a.md")])], nil)
        }, read: { uri in
            uri == "volant://snippets" ? [.object(["uri": .string(uri), "mimeType": .string("application/json"), "text": .string("[]")])] : nil
        }, templates: [.object(["uriTemplate": .string("volant://notes/{id}"), "name": .string("note")])])
        return MCPSession(version: "1", instructions: "", tools: { [] }, resources: { sharing ? resources : nil })
    }

    private func send(_ session: MCPSession, _ method: String, _ params: [String: MCPValue] = [:], legacy: Bool = false) async throws -> MCPValue? {
        var params = params
        if !legacy { params["_meta"] = meta }
        let reply = await session.handle(MCPValue.object(["jsonrpc": .string("2.0"), "id": .int(1), "method": .string(method), "params": .object(params)]).line())
        return try reply.map { try JSONDecoder().decode(MCPValue.self, from: $0) }
    }

    func testListPagesReadsAndTemplates() async throws {
        let session = session()
        let discover = try await send(session, "server/discover")
        XCTAssertEqual(discover?["result"]?["capabilities"]?["resources"], .object([:]))
        let first = try await send(session, "resources/list")
        XCTAssertEqual(first?["result"]?["nextCursor"], .string("page-2"))
        let second = try await send(session, "resources/list", ["cursor": .string("page-2")])
        XCTAssertNil(second?["result"]?["nextCursor"])
        let read = try await send(session, "resources/read", ["uri": .string("volant://snippets")])
        XCTAssertEqual(read?["result"]?["contents"], .array([.object(["uri": .string("volant://snippets"), "mimeType": .string("application/json"), "text": .string("[]")])]))
        let templates = try await send(session, "resources/templates/list")
        XCTAssertNotNil(templates?["result"]?["resourceTemplates"])
    }

    func testUnknownResourcesUseEachRevisionsCode() async throws {
        let modern = try await send(session(), "resources/read", ["uri": .string("volant://notes/missing.md")])
        XCTAssertEqual(modern?["error"]?["code"], .int(-32602))
        XCTAssertEqual(modern?["error"]?["data"]?["uri"], .string("volant://notes/missing.md"))
        let legacy = session()
        _ = await legacy.handle(MCPValue.object(["jsonrpc": .string("2.0"), "id": .int(0), "method": .string("initialize"),
                                                 "params": .object(["protocolVersion": .string("2025-06-18")])]).line())
        let old = try await send(legacy, "resources/read", ["uri": .string("volant://nope")], legacy: true)
        XCTAssertEqual(old?["error"]?["code"], .int(-32002))
        let noURI = try await send(session(), "resources/read")
        XCTAssertEqual(noURI?["error"]?["code"], .int(-32602))
    }

    func testNoResourcesWhenNotShared() async throws {
        let session = session(sharing: false)
        let discover = try await send(session, "server/discover")
        XCTAssertNil(discover?["result"]?["capabilities"]?["resources"])
        let list = try await send(session, "resources/list")
        XCTAssertEqual(list?["error"]?["code"], .int(-32601))
    }
}

final class MCPPreferencesTests: XCTestCase {
    func testOffByDefaultTolerantAndNeverSynced() throws {
        XCTAssertEqual(Preferences().mcpServer, MCPPreferences())
        XCTAssertFalse(MCPPreferences().enabled)
        let decoded = try JSONDecoder().decode(MCPPreferences.self, from: Data(#"{"enabled":"yes","writesNotes":true,"knownClients":["Cursor","bad name","cursor"],"future":1}"#.utf8))
        XCTAssertFalse(decoded.enabled)
        XCTAssertTrue(decoded.writesNotes)
        XCTAssertEqual(decoded.knownClients, ["cursor"])
        XCTAssertFalse(SettingsSync.keys.contains("mcpServer"))
    }

    func testAlwaysAllowIsPerClientAndToolAndDisconnectClearsIt() throws {
        var preferences = try JSONDecoder().decode(MCPPreferences.self, from: Data(#"{"alwaysAllowed":["cursor/search_clipboard","bad","Bad Name/x","cursor/","codex/search_files","cursor/search_clipboard"]}"#.utf8))
        XCTAssertEqual(preferences.alwaysAllowed, ["cursor/search_clipboard", "codex/search_files"])
        XCTAssertTrue(preferences.alwaysAllows(client: "cursor", tool: "search_clipboard"))
        XCTAssertFalse(preferences.alwaysAllows(client: "cursor", tool: "search_files"))
        XCTAssertFalse(preferences.sharesClipboard, "Sensitive switches are off by default")
        preferences.disconnect("cursor")
        XCTAssertEqual(preferences.alwaysAllowed, ["codex/search_files"])
        XCTAssertEqual(preferences.disconnectedClients, ["cursor"])
        preferences.askAgain("codex")
        XCTAssertEqual(preferences.alwaysAllowed, [])
    }

    func testRefusalFollowsTheSwitchAndDisconnectedApps() {
        XCTAssertEqual(MCPPreferences().refusal(for: "cursor"), .serverOff)
        let on = MCPPreferences(enabled: true, disconnectedClients: ["codex"])
        XCTAssertNil(on.refusal(for: "cursor"))
        XCTAssertEqual(on.refusal(for: "codex"), .disconnected)
    }

    func testUpdateKeepsUnknownKeysAndRefusesStaleCopies() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".json")
        defer { try? FileManager.default.removeItem(at: url) }
        try Data(#"{"future":1,"mcpServer":{"later":"kept"}}"#.utf8).write(to: url)
        let loaded = try JSONDecoder().decode(Preferences.self, from: Data(contentsOf: url))
        var updated = loaded.mcpServer
        updated.enabled = true
        try Preferences.updateMCPServer(updated, expected: loaded.mcpServer, at: url)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        XCTAssertEqual(object["future"] as? Int, 1)
        XCTAssertEqual((object["mcpServer"] as? [String: Any])?["later"] as? String, "kept")
        XCTAssertThrowsError(try Preferences.updateMCPServer(MCPPreferences(), expected: loaded.mcpServer, at: url))
    }
}

final class MCPBridgeReplayTests: XCTestCase {
    private func line(_ value: MCPValue) -> Data { value.line() }

    func testModernClientsNeedNoReplay() {
        var replay = MCPBridgeReplay()
        replay.observe(line(.object(["jsonrpc": .string("2.0"), "id": .int(1), "method": .string("tools/list"),
                                     "params": .object(["_meta": .object(["io.modelcontextprotocol/protocolVersion": .string("2026-07-28")])])])))
        XCTAssertEqual(replay.lines(), [])
    }

    func testLegacyHandshakeIsReplayedUnderTheBridgesIdAndItsReplyDropped() async throws {
        var replay = MCPBridgeReplay()
        let params: MCPValue = .object(["protocolVersion": .string("2025-06-18"), "capabilities": .object([:])])
        replay.observe(line(.object(["jsonrpc": .string("2.0"), "id": .int(0), "method": .string("initialize"), "params": params])))
        XCTAssertEqual(replay.lines().count, 1, "Before initialized, only initialize is replayed")
        replay.observe(line(.object(["jsonrpc": .string("2.0"), "method": .string("notifications/initialized")])))
        let lines = replay.lines()
        XCTAssertEqual(lines.count, 2)
        let replayed = try JSONDecoder().decode(MCPValue.self, from: lines[0])
        XCTAssertEqual(replayed["id"], .string(MCPBridgeReplay.replayID))
        XCTAssertEqual(replayed["params"], params)

        let session = MCPSession(version: "1", instructions: "", tools: { [] })
        let replyLine = await session.handle(lines[0])
        let reply = try XCTUnwrap(replyLine)
        XCTAssertTrue(MCPBridgeReplay.isReplayReply(reply))
        let initializedReply = await session.handle(lines[1])
        XCTAssertNil(initializedReply)
        let listLine = await session.handle(line(.object(["jsonrpc": .string("2.0"), "id": .int(5), "method": .string("tools/list")])))
        let list = try XCTUnwrap(listLine)
        XCTAssertFalse(MCPBridgeReplay.isReplayReply(list))
        XCTAssertNotNil(try JSONDecoder().decode(MCPValue.self, from: list)["result"], "A fresh session accepts the client's legacy requests after the replay")
    }
}
