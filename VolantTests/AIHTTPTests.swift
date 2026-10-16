import XCTest
import VolantCore
@testable import Volant

final class AIHTTPTests: XCTestCase {
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
        let model = isolatedACPModel(); model.configure(config); model.state.phase = "working"; model.draft = "Keep this"
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
