import XCTest
@testable import Volant

final class StatusSourceTests: XCTestCase {
    func testIndependentPinsPreserveOtherSourcesAndUnknownFields() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: url) }
        try Data(#"{"statusBar":{"sources":["herdr","future-source"],"herdrFilter":"claude","future":7},"unrelated":true}"#.utf8).write(to: url)
        try Preferences.updateStatusBar(source: "ai-chat", enabled: true, at: url)
        try Preferences.updateStatusBar(enabled: false, at: url)
        var decoded = try JSONDecoder().decode(Preferences.self, from: Data(contentsOf: url))
        XCTAssertEqual(decoded.statusBar.sources, ["future-source", "ai-chat"])
        XCTAssertEqual(decoded.statusBar.herdrFilter, "claude")
        decoded.promotedHarness = "codex"
        XCTAssertTrue(decoded.statusBar.sources.contains("ai-chat"))
        decoded.promotedHarness = nil
        XCTAssertEqual(decoded.statusBar.sources, ["future-source", "ai-chat"])
        try Preferences.updateStatusBar(source: "ai-chat", enabled: false, at: url)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        let bar = try XCTUnwrap(object["statusBar"] as? [String: Any])
        XCTAssertEqual(bar["sources"] as? [String], ["future-source"])
        XCTAssertEqual(bar["future"] as? Int, 7)
        XCTAssertEqual(object["unrelated"] as? Bool, true)
    }

    func testAIStatusIsOptInAndUnsupportedSourceDoesNotWrite() throws {
        XCTAssertFalse(Preferences().statusBar.sources.contains("ai-chat"))
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: url) }
        let original = Data("{}".utf8)
        try original.write(to: url)
        XCTAssertThrowsError(try Preferences.updateStatusBar(source: "unimplemented", enabled: true, at: url))
        XCTAssertEqual(try Data(contentsOf: url), original)
    }
}
