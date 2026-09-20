import XCTest
import VolantCore
@testable import Volant

final class AIHTTPTests: XCTestCase {
    func testEndpointValidationAndCredentialIsolation() throws {
        for endpoint in ["http://example.com/v1", "https://name:secret@example.com/v1", "https://example.com/v1?key=secret", "https://example.com/v1#fragment"] {
            XCTAssertThrowsError(try VolantCore.AIHTTPConfiguration(provider: .compatible, endpoint: endpoint).validate(requireModel: false))
        }
        for endpoint in ["http://localhost:1234/v1", "http://127.0.0.1:11434/v1", "http://[::1]:1234/v1"] {
            XCTAssertNoThrow(try VolantCore.AIHTTPConfiguration(provider: .compatible, endpoint: endpoint, local: true).validate(requireModel: false))
        }
        XCTAssertThrowsError(try VolantCore.AIHTTPConfiguration(provider: .compatible, endpoint: "https://example.com/v1", local: true).validate(requireModel: false))
        XCTAssertThrowsError(try VolantCore.AIHTTPConfiguration(provider: .openAI, endpoint: "https://example.com/v1").validate(requireModel: false))
        let first = VolantCore.AIHTTPConfiguration(provider: .compatible, endpoint: "https://one.example/v1")
        let second = VolantCore.AIHTTPConfiguration(provider: .compatible, endpoint: "https://two.example/v1")
        XCTAssertNotEqual(first.credentialID, second.credentialID)
    }
    func testProviderRequestShapesAndNoTools() throws {
        let transport = VolantCore.AIHTTPTransport()
        let messages = [VolantCore.ACPMessage(role: "You", text: "Fictional question"), VolantCore.ACPMessage(role: "Agent", text: "Answer")]
        for provider in VolantCore.AIAPIProvider.allCases {
            let config = VolantCore.AIHTTPConfiguration(provider: provider, endpoint: provider == .compatible ? "https://test.example/v1" : provider.endpoint, model: "fixture-model")
            let request = try transport.chatRequest(config, key: "fictional-key", messages: messages)
            let body = try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(request.httpBody)) as? [String: Any])
            XCTAssertEqual(body["model"] as? String, "fixture-model")
            XCTAssertEqual(body["stream"] as? Bool, true)
            XCTAssertNil(body["tools"])
            XCTAssertNil(body["api_key"])
            if provider == .openAI { XCTAssertEqual(body["store"] as? Bool, false); XCTAssertNotNil(body["input"]) }
            else { XCTAssertNotNil(body["messages"]) }
            if provider == .anthropic { XCTAssertEqual(request.value(forHTTPHeaderField: "x-api-key"), "fictional-key") }
            else { XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer fictional-key") }
        }
        let local = VolantCore.AIHTTPConfiguration(provider: .compatible, endpoint: "http://127.0.0.1:1234/v1", model: "fixture", local: true)
        XCTAssertNil(try transport.chatRequest(local, key: "", messages: messages).value(forHTTPHeaderField: "Authorization"))
        XCTAssertThrowsError(try transport.chatRequest(VolantCore.AIHTTPConfiguration(model: "fixture"), key: "", messages: messages))
    }
    func testStreamingFramesUnicodeAndProviderCompletion() throws {
        let fixtures: [(VolantCore.AIAPIProvider, String)] = [
            (.openAI, "data: {\"type\":\"response.output_text.delta\",\"delta\":\"café ☕\"}\r\n\r\ndata: {\"type\":\"response.completed\"}\n\n"),
            (.anthropic, "event: content_block_delta\ndata: {\"type\":\"content_block_delta\",\"delta\":{\"type\":\"text_delta\",\"text\":\"café ☕\"}}\n\ndata: {\"type\":\"message_stop\"}\n\n"),
            (.compatible, "data: {\"choices\":[{\"delta\":{\"content\":\"café ☕\"}}]}\n\ndata: [DONE]\n\n")
        ]
        for (provider, wire) in fixtures {
            var decoder = VolantCore.AIStreamDecoder(provider: provider), text = ""
            for byte in wire.utf8 { text += try decoder.feed(byte) }
            XCTAssertEqual(text, "café ☕"); XCTAssertTrue(decoder.finished)
        }
    }
    func testMalformedTruncatedOversizedAndUnsupportedStreams() throws {
        var incomplete = VolantCore.AIStreamDecoder(provider: .compatible)
        for byte in "data: {\"choices\":[]}\n\n".utf8 { _ = try incomplete.feed(byte) }
        XCTAssertFalse(incomplete.finished)
        for frame in ["data: not json\n\n", "data: {\"error\":{}}\n\n", "data: {\"choices\":[{\"delta\":{\"tool_calls\":[]}}]}\n\n", "data: {\"choices\":[{\"finish_reason\":\"length\"}]}\n\n", String(repeating: "x", count: 65_537)] {
            var decoder = VolantCore.AIStreamDecoder(provider: .compatible)
            XCTAssertThrowsError(try frame.utf8.forEach { _ = try decoder.feed($0) })
        }
    }
    func testAPIConfigMigrationPreservesNestedUnknownValuesAndActiveChat() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: url) }
        try Data(#"{"ai":{"provider":"claude","project":"","future":true}}"#.utf8).write(to: url)
        let old = try AIConfiguration.load(at: url)
        XCTAssertEqual(old.connection, .acp)
        var config = old; config.connection = .byok; config.api.model = "fictional-model"
        try config.save(at: url, expected: old)
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        var ai = json["ai"] as! [String: Any], api = ai["api"] as! [String: Any]
        api["future"] = 42; ai["api"] = api; json["ai"] = ai
        try JSONSerialization.data(withJSONObject: json).write(to: url)
        var next = config; next.api.model = "second-model"
        try next.save(at: url, expected: config)
        let saved = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        XCTAssertEqual(((saved["ai"] as? [String: Any])?["api"] as? [String: Any])?["future"] as? Int, 42)
        XCTAssertFalse(String(decoding: try Data(contentsOf: url), as: UTF8.self).contains("api_key"))
        let model = ACPModel(); model.configure(config); model.state.phase = "working"; model.draft = "Keep this"
        model.configure(old)
        XCTAssertTrue(model.usesAPI); XCTAssertEqual(model.providerTitle, "fictional-model"); XCTAssertEqual(model.draft, "Keep this")
        model.state.phase = "disconnected"
    }
    func testDiscoveryRejectsLateResultsAfterSwitchingOrClosing() {
        let model = AIModelDiscovery()
        var replies: [([String]?, String?) -> Void] = []
        model.lookupOverride = { _, _, reply in replies.append(reply) }
        model.discover(); XCTAssertEqual(replies.count, 3)
        replies[0](["fixture"], nil); XCTAssertEqual(model.servers[0].models, ["fixture"])
        model.cancel(); replies[1](["stale"], nil); XCTAssertTrue(model.servers[1].models.isEmpty)
        model.refresh(VolantCore.AIHTTPConfiguration(), key: "")
        model.cancel(); replies.last?(["stale"], nil); XCTAssertTrue(model.models.isEmpty)
        let server = VolantCore.AILocalServer(name: "Fixture", endpoint: "http://127.0.0.1:1234/v1", models: ["one", "two"])
        model.select(server); model.endpointChanged(server.endpoint)
        XCTAssertEqual(model.models, ["one", "two"], "Selecting a discovered endpoint retains its model choices")
        model.endpointChanged("http://127.0.0.1:8000/v1")
        XCTAssertTrue(model.models.isEmpty, "Model choices cannot leak into a different endpoint")
    }
}
