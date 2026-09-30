import XCTest

@testable import VolantCore

/// Theme, size and opacity are edited from Settings as one patch to the appearance block.
final class AppearanceTests: XCTestCase {
    private var url: URL!

    override func setUpWithError() throws {
        url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".json")
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: url)
    }

    func testPartialAndUnknownAppearanceStillLoads() throws {
        let partial = try JSONDecoder().decode(Preferences.self, from: Data(#"{"appearance":{"scale":1.2}}"#.utf8))
        XCTAssertEqual(partial.appearance.scale, 1.2)
        XCTAssertEqual(partial.appearance.opacity, 1.0)
        XCTAssertEqual(partial.appearance.theme, .system)
        let unknown = try JSONDecoder().decode(Preferences.self, from: Data(#"{"appearance":{"theme":"sepia"}}"#.utf8))
        XCTAssertEqual(unknown.appearance.theme, .system, "an unknown theme follows the system")
    }

    func testUpdatePreservesUnknownFieldsAndClamps() throws {
        try Data(#"{"summonHotKey":"option+space","appearance":{"scale":1.0,"future":7},"other":{"keep":true}}"#.utf8).write(to: url)
        let expected = try JSONDecoder().decode(Preferences.self, from: Data(contentsOf: url)).appearance
        try Preferences.updateAppearance(Appearance(theme: .dark, scale: 3, opacity: 0.1), expected: expected, at: url)
        let object = try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as! [String: Any]
        let block = object["appearance"] as! [String: Any]
        XCTAssertEqual(block["theme"] as? String, "dark")
        XCTAssertEqual(block["scale"] as? Double, 1.4)
        XCTAssertEqual(block["opacity"] as? Double, 0.5)
        XCTAssertEqual(block["future"] as? Int, 7)
        XCTAssertEqual((object["other"] as? [String: Bool])?["keep"], true)
        XCTAssertEqual(object["summonHotKey"] as? String, "option+space")
    }

    func testStaleSnapshotIsRejectedWithoutWriting() throws {
        try Data(#"{"appearance":{"theme":"light"}}"#.utf8).write(to: url)
        let saved = try Data(contentsOf: url)
        XCTAssertThrowsError(try Preferences.updateAppearance(Appearance(theme: .dark), expected: Appearance(), at: url))
        XCTAssertEqual(try Data(contentsOf: url), saved)
    }
}
