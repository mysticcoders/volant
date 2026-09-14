import XCTest
@testable import Volant

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

    func testMalformedConfigIsNotOverwritten() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: url) }
        let data = Data("broken json".utf8)
        try data.write(to: url)
        XCTAssertThrowsError(try Preferences.updateBoolean("showInDock", value: true, at: url))
        XCTAssertEqual(try Data(contentsOf: url), data)
    }
}
