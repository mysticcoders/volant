import XCTest
@testable import Volant

final class AIConfigurationTests: XCTestCase {
    func testACPSettingsPreserveUnknownFieldsAndRejectStaleWrites() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: url) }
        try Data(#"{"future":true,"ai":{"future":42}}"#.utf8).write(to: url)
        let original = try AIConfiguration.load(at: url)
        XCTAssertEqual(original.provider, "opencode")
        var changed = original; changed.provider = "claude"; changed.project = "/tmp/fictional-project"
        try changed.save(at: url, expected: original)
        XCTAssertEqual(try AIConfiguration.load(at: url), changed)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        XCTAssertEqual(object["future"] as? Bool, true)
        XCTAssertEqual((object["ai"] as? [String: Any])?["future"] as? Int, 42)
        let before = try Data(contentsOf: url)
        XCTAssertThrowsError(try original.save(at: url, expected: original))
        changed.provider = "unsupported"
        XCTAssertThrowsError(try changed.save(at: url))
        XCTAssertEqual(try Data(contentsOf: url), before)
        try Data("broken".utf8).write(to: url)
        XCTAssertThrowsError(try AIConfiguration.load(at: url))
        XCTAssertThrowsError(try original.save(at: url))
        XCTAssertEqual(try Data(contentsOf: url), Data("broken".utf8))
    }
    func testConfiguringACPDoesNotReplaceActiveConversation() {
        let model = ACPModel()
        var config = AIConfiguration(); config.provider = "codex"; config.project = "/tmp/project"
        model.configure(config)
        XCTAssertEqual(model.provider, "codex")
        XCTAssertEqual(model.project, "/tmp/project")
        XCTAssertFalse(model.active)
        model.state.phase = "working"
        config.provider = "claude"; config.project = "/tmp/other"
        model.configure(config)
        XCTAssertEqual(model.provider, "codex")
        XCTAssertEqual(model.project, "/tmp/project")
        model.state.phase = "disconnected"
    }
}
