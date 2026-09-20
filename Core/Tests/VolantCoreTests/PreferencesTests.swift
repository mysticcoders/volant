import XCTest

@testable import VolantCore

final class PreferencesTests: XCTestCase {
    func testDockSettingPreservesOtherFields() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: url) }
        try Data(#"{"aliases":{"s":"Safari"},"future":{"keep":1}}"#.utf8).write(to: url)
        try Preferences.updateBoolean("showInDock", value: false, at: url)
        let data = try Data(contentsOf: url)
        let config = try JSONDecoder().decode(Preferences.self, from: data)
        XCTAssertFalse(config.showInDock)
        XCTAssertEqual(config.aliases["s"], "Safari")
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertNotNil(object["future"])
    }

    func testPinnedHarnessRoundTripPreservesOtherSettings() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: url) }
        try Data(#"{"aliases":{"s":"Safari"},"future":true}"#.utf8).write(to: url)
        try Preferences.updatePromotedHarness("codex", at: url)
        var data = try Data(contentsOf: url)
        XCTAssertEqual(try JSONDecoder().decode(Preferences.self, from: data).promotedHarness, "codex")
        XCTAssertThrowsError(try Preferences.updatePromotedHarness("unsupported", at: url))
        XCTAssertEqual(try Data(contentsOf: url), data)
        try Preferences.updatePromotedHarness(nil, at: url)
        data = try Data(contentsOf: url)
        let config = try JSONDecoder().decode(Preferences.self, from: data)
        XCTAssertNil(config.promotedHarness)
        XCTAssertEqual(config.aliases["s"], "Safari")
        XCTAssertEqual((try JSONSerialization.jsonObject(with: data) as? [String: Any])?["future"] as? Bool, true)
    }

    func testStatusBarMigratesLegacyAndPreservesFutureSources() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: url) }
        try Data(#"{"promotedHarness":"claude","future":true}"#.utf8).write(to: url)
        var config = try JSONDecoder().decode(Preferences.self, from: Data(contentsOf: url))
        XCTAssertEqual(config.statusBar.sources, ["herdr"])
        XCTAssertEqual(config.statusBar.herdrFilter, "claude")
        try Preferences.updateStatusBar(enabled: false, at: url)
        config = try JSONDecoder().decode(Preferences.self, from: Data(contentsOf: url))
        XCTAssertNil(config.promotedHarness)
        XCTAssertEqual(config.statusBar.herdrFilter, "claude")
        try Preferences.updateStatusBar(enabled: true, at: url)
        XCTAssertEqual(try JSONDecoder().decode(Preferences.self, from: Data(contentsOf: url)).promotedHarness, "claude")
        try Data(#"{"promotedHarness":"codex","statusBar":{"sources":["herdr","future"],"herdrFilter":"all","unknown":42}}"#.utf8).write(to: url)
        try Preferences.updateStatusBar(enabled: false, at: url)
        config = try JSONDecoder().decode(Preferences.self, from: Data(contentsOf: url))
        XCTAssertEqual(config.statusBar.sources, ["future"])
        XCTAssertNil(config.promotedHarness)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        XCTAssertNil(object["promotedHarness"])
        XCTAssertEqual((object["statusBar"] as? [String: Any])?["unknown"] as? Int, 42)
    }

    func testMalformedConfigIsNotOverwritten() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: url) }
        let data = Data("broken json".utf8)
        try data.write(to: url)
        XCTAssertThrowsError(try Preferences.updateBoolean("showInDock", value: true, at: url))
        XCTAssertEqual(try Data(contentsOf: url), data)
    }
}
