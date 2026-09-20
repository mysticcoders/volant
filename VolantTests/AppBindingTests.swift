import XCTest
import VolantCore
@testable import Volant

final class AppBindingTests: XCTestCase {
    func testGlyphFormattingPreservesCanonicalInput() {
        XCTAssertEqual(KeyCombo.display("hyper+c"), "✦ C")
        XCTAssertEqual(KeyCombo.display("cmd+ctrl+option+shift+c"), "✦ C")
        XCTAssertEqual(KeyCombo.display("cmd+ctrl+space"), "⌃⌘ ␣")
        XCTAssertEqual(KeyCombo.display("option+n"), "⌥ N")
        XCTAssertEqual(KeyCombo.display("shift+return"), "⇧ ↩")
        XCTAssertEqual(KeyCombo.display("meh+left"), "⌃⌥⇧ ←")
        XCTAssertEqual(KeyCombo.display(""), "")
        XCTAssertEqual(KeyCombo(parsing: "hyper+c"), KeyCombo(parsing: "cmd+ctrl+option+shift+c"))
    }
    func testInlineAliasPreservesOtherFieldsAndRejectsStaleEdits() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent("config.json")
        let original = #"{"aliases":{"old":"/Fixture.app","another":"/Fixture.app","keep":"/Other.app"},"unknown":{"preserve":true},"appHotKeys":[{"bundleIdentifier":"test.fixture","hotKey":"hyper+c","future":7}]}"#
        try Data(original.utf8).write(to: url)
        let expected = ["old": "/Fixture.app", "another": "/Fixture.app"]
        try AppBindingStore.updateAlias(path: "/Fixture.app", name: "Fixture", originalAlias: "old", value: "new", expectedAliases: expected, at: url)
        let object = try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as! [String: Any]
        XCTAssertEqual(object["aliases"] as? [String: String], ["new": "/Fixture.app", "another": "/Fixture.app", "keep": "/Other.app"])
        XCTAssertEqual((object["unknown"] as? [String: Bool])?["preserve"], true)
        XCTAssertEqual((object["appHotKeys"] as? [[String: Any]])?.first?["future"] as? Int, 7)
        let saved = try Data(contentsOf: url)
        XCTAssertThrowsError(try AppBindingStore.updateAlias(path: "/Fixture.app", name: "Fixture", originalAlias: "old", value: "stale", expectedAliases: expected, at: url))
        XCTAssertEqual(try Data(contentsOf: url), saved)
        for invalid in ["emoji", "caffeinate", "two words", "keep"] {
            XCTAssertThrowsError(try AppBindingStore.updateAlias(path: "/Fixture.app", name: "Fixture", originalAlias: "new", value: invalid, expectedAliases: ["new": "/Fixture.app", "another": "/Fixture.app"], at: url))
            XCTAssertEqual(try Data(contentsOf: url), saved)
        }
        try AppBindingStore.updateAlias(path: "/Fixture.app", name: "Fixture", originalAlias: "new", value: "", expectedAliases: ["new": "/Fixture.app", "another": "/Fixture.app"], at: url)
        let latest = try JSONDecoder().decode(Preferences.self, from: Data(contentsOf: url))
        XCTAssertNil(latest.aliases["new"])
        XCTAssertEqual(latest.aliases["another"], "/Fixture.app")
    }
}
