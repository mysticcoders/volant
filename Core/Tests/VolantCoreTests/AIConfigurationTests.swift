import XCTest

@testable import VolantCore

/// AI chat settings keep unknown config fields and refuse stale or unsupported writes, and the
/// ACP working directory is the internal general-chat folder unless an absolute folder is chosen.
final class AIConfigurationTests: XCTestCase {
    func testACPSettingsPreserveUnknownFieldsAndRejectStaleWrites() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: url) }
        try Data(#"{"future":true,"ai":{"future":42}}"#.utf8).write(to: url)
        let original = try AIConfiguration.load(at: url)
        XCTAssertFalse(original.isConfigured)
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

    func testGeneralChatDirectoryAndExplicitFolderValidation() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let general = root.appendingPathComponent("Chat")
        XCTAssertEqual(try ACPWorkingDirectory.resolve(project: "", generalChat: general), general.resolvingSymlinksInPath().path)
        XCTAssertEqual(try ACPWorkingDirectory.resolve(project: root.path, generalChat: general), root.resolvingSymlinksInPath().path)
        XCTAssertThrowsError(try ACPWorkingDirectory.resolve(project: "relative", generalChat: general))
        XCTAssertThrowsError(try ACPWorkingDirectory.resolve(project: root.appendingPathComponent("missing").path, generalChat: general))
    }
}
