import XCTest

@testable import VolantCore

/// BYOK and local chat requests: endpoint validation, per-provider request shapes without tools,
/// and the streaming decoder's handling of complete, truncated, malformed and oversized frames.
final class AIHTTPTransportTests: XCTestCase {
    func testEndpointValidationAndCredentialIsolation() throws {
        for endpoint in ["http://example.com/v1", "https://name:secret@example.com/v1", "https://example.com/v1?key=secret", "https://example.com/v1#fragment"] {
            XCTAssertThrowsError(try AIHTTPConfiguration(provider: .compatible, endpoint: endpoint).validate(requireModel: false))
        }
        for endpoint in ["http://localhost:1234/v1", "http://127.0.0.1:11434/v1", "http://[::1]:1234/v1"] {
            XCTAssertNoThrow(try AIHTTPConfiguration(provider: .compatible, endpoint: endpoint, local: true).validate(requireModel: false))
        }
        XCTAssertThrowsError(try AIHTTPConfiguration(provider: .compatible, endpoint: "https://example.com/v1", local: true).validate(requireModel: false))
        XCTAssertThrowsError(try AIHTTPConfiguration(provider: .openAI, endpoint: "https://example.com/v1").validate(requireModel: false))
        let first = AIHTTPConfiguration(provider: .compatible, endpoint: "https://one.example/v1")
        let second = AIHTTPConfiguration(provider: .compatible, endpoint: "https://two.example/v1")
        XCTAssertNotEqual(first.credentialID, second.credentialID)
    }

    func testProviderRequestShapesAndNoTools() throws {
        let transport = AIHTTPTransport()
        let messages = [ACPMessage(role: "You", text: "Fictional question"), ACPMessage(role: "Agent", text: "Answer")]
        for provider in AIAPIProvider.allCases {
            let config = AIHTTPConfiguration(provider: provider, endpoint: provider == .compatible ? "https://test.example/v1" : provider.endpoint, model: "fixture-model")
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
        let local = AIHTTPConfiguration(provider: .compatible, endpoint: "http://127.0.0.1:1234/v1", model: "fixture", local: true)
        XCTAssertNil(try transport.chatRequest(local, key: "", messages: messages).value(forHTTPHeaderField: "Authorization"))
        XCTAssertThrowsError(try transport.chatRequest(AIHTTPConfiguration(model: "fixture"), key: "", messages: messages))
    }

    func testStreamingFramesUnicodeAndProviderCompletion() throws {
        let fixtures: [(AIAPIProvider, String)] = [
            (.openAI, "data: {\"type\":\"response.output_text.delta\",\"delta\":\"café ☕\"}\r\n\r\ndata: {\"type\":\"response.completed\"}\n\n"),
            (.anthropic, "event: content_block_delta\ndata: {\"type\":\"content_block_delta\",\"delta\":{\"type\":\"text_delta\",\"text\":\"café ☕\"}}\n\ndata: {\"type\":\"message_stop\"}\n\n"),
            (.compatible, "data: {\"choices\":[{\"delta\":{\"content\":\"café ☕\"}}]}\n\ndata: [DONE]\n\n")
        ]
        for (provider, wire) in fixtures {
            var decoder = AIStreamDecoder(provider: provider), text = ""
            for byte in wire.utf8 { text += try decoder.feed(byte) }
            XCTAssertEqual(text, "café ☕"); XCTAssertTrue(decoder.finished)
        }
    }

    func testMalformedTruncatedOversizedAndUnsupportedStreams() throws {
        var incomplete = AIStreamDecoder(provider: .compatible)
        for byte in "data: {\"choices\":[]}\n\n".utf8 { _ = try incomplete.feed(byte) }
        XCTAssertFalse(incomplete.finished)
        for frame in ["data: not json\n\n", "data: {\"error\":{}}\n\n", "data: {\"choices\":[{\"delta\":{\"tool_calls\":[]}}]}\n\n", "data: {\"choices\":[{\"finish_reason\":\"length\"}]}\n\n", String(repeating: "x", count: 65_537)] {
            var decoder = AIStreamDecoder(provider: .compatible)
            XCTAssertThrowsError(try frame.utf8.forEach { _ = try decoder.feed($0) })
        }
    }
}
