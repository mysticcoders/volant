import XCTest

@testable import VolantCore

/// Older config files still decode with defaults for newer sections, and the narrow favorite and
/// status-bar patches keep unknown fields and refuse stale or unsupported edits.
final class PreferencesPatchTests: XCTestCase {
    func testOlderConfigStillDecodes() throws {
        let json = #"{"summonHotKey":"cmd+space","appHotKeys":[{"bundleIdentifier":"md.obsidian","hotKey":"cmd+ctrl+o"}],"clipboardRetention":250}"#
        let prefs = try JSONDecoder().decode(Preferences.self, from: Data(json.utf8))
        XCTAssertEqual(prefs.summonHotKey, "cmd+space")
        XCTAssertEqual(prefs.clipboardRetention, 250)
        XCTAssertEqual(prefs.notesHotKey, Preferences().notesHotKey)
        XCTAssertEqual(prefs.appHotKeys.count, 1)
    }

    func testOlderConfigWithoutNewSectionsStillLoads() throws {
        let prefs = try JSONDecoder().decode(Preferences.self, from: Data(#"{"summonHotKey":"cmd+space"}"#.utf8))
        XCTAssertEqual(prefs.quicklinks.first?.name, "Google")
        XCTAssertTrue(prefs.snippets.isEmpty)
        XCTAssertEqual(prefs.appearance.scale, 1.0)
    }

    func testFavoritePatchPreservesUnknownFieldsAndRejectsStaleMembership() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".json")
        defer { try? FileManager.default.removeItem(at: url) }
        try Data(#"{"future":{"enabled":true},"favoriteApps":["other"]}"#.utf8).write(to: url)
        let added = try Preferences.updateFavorite("fixture", expected: false, at: url)
        XCTAssertEqual(added.favoriteApps, ["other", "fixture"])
        let saved = try Data(contentsOf: url)
        XCTAssertThrowsError(try Preferences.updateFavorite("fixture", expected: false, at: url))
        XCTAssertEqual(try Data(contentsOf: url), saved)
        XCTAssertEqual(try Preferences.updateFavorite("fixture", expected: true, at: url).favoriteApps, ["other"])
        let object = try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any]
        XCTAssertEqual((object?["future"] as? [String: Bool])?["enabled"], true)
    }

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
