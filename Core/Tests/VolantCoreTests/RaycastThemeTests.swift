import XCTest

@testable import VolantCore

/// Raycast theme files and links are decoded locally into imported color themes; all fixtures are fictional.
final class RaycastThemeTests: XCTestCase {
    private var url: URL!
    private let colors = ["#101418", "#0C1014", "#E8ECF0", "#2A3440", "#7A8490",
                          "#F06060", "#F09050", "#E8C860", "#70C080", "#6CA8F0", "#A890F0", "#E080C8"]

    override func setUpWithError() throws {
        url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".json")
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: url)
    }

    private var json: String {
        let pairs = zip(RaycastTheme.colorKeys, colors).map { "\"\($0)\": \"\($1)\"" }.joined(separator: ", ")
        return #"{"author": "Fixture Author", "authorUsername": "fixture", "version": "1", "name": "Harbor Night", "appearance": "dark", "colors": {"# + pairs + "}}"
    }

    private var link: String {
        "raycast://theme?version=1&name=Harbor%20Night&author=Fixture%20Author&appearance=dark&colors="
            + colors.map { $0.replacingOccurrences(of: "#", with: "%23") }.joined(separator: ",")
    }

    func testJSONAndLinkDecodeToTheSameTheme() throws {
        let fromJSON = try RaycastTheme.parse(json)
        let fromLink = try RaycastTheme.parse(link)
        XCTAssertEqual(fromJSON, fromLink)
        XCTAssertEqual(fromJSON.name, "Harbor Night")
        XCTAssertEqual(fromJSON.author, "Fixture Author")
        XCTAssertEqual(fromJSON.mode, .dark)
        XCTAssertEqual(fromJSON.colors["background"], "#101418")
        XCTAssertEqual(fromJSON.colors["magenta"], "#e080c8")
    }

    func testWebLinksWithColorsAndLegacyAlphaAreAccepted() throws {
        let web = link.replacingOccurrences(of: "raycast://theme?", with: "https://themes.ray.so/?")
        XCTAssertEqual(try RaycastTheme.parse(web).name, "Harbor Night")
        let legacy = link.replacingOccurrences(of: "%23101418", with: "%23101418FF")
        XCTAssertEqual(try RaycastTheme.parse(legacy).colors["background"], "#101418")
        let internalFlavor = link.replacingOccurrences(of: "raycast://", with: "raycastinternal://")
        XCTAssertEqual(try RaycastTheme.parse(internalFlavor).name, "Harbor Night")
    }

    func testRejectsShareLinksWithoutColorsAndOtherInput() {
        XCTAssertThrowsError(try RaycastTheme.parse("https://themes.ray.so/fixture/harbor-night")) {
            XCTAssertEqual($0 as? RaycastTheme.ParseError, .shareLinkWithoutColors)
        }
        XCTAssertThrowsError(try RaycastTheme.parse("https://example.com/theme?colors=%23000000")) {
            XCTAssertEqual($0 as? RaycastTheme.ParseError, .notATheme)
        }
        XCTAssertThrowsError(try RaycastTheme.parse("raycast://extensions/fixture"))
        XCTAssertThrowsError(try RaycastTheme.parse("not a theme"))
        XCTAssertThrowsError(try RaycastTheme.parse(link.replacingOccurrences(of: "appearance=dark", with: "appearance=sepia")))
        XCTAssertThrowsError(try RaycastTheme.parse(link.replacingOccurrences(of: ",%23E080C8", with: ""))) {
            XCTAssertEqual($0 as? RaycastTheme.ParseError, .missingColors)
        }
        XCTAssertThrowsError(try RaycastTheme.parse(link.replacingOccurrences(of: "%236CA8F0", with: "blue"))) {
            XCTAssertEqual($0 as? RaycastTheme.ParseError, .invalidColor("blue"))
        }
        XCTAssertThrowsError(try RaycastTheme.parse(json.replacingOccurrences(of: "\"name\": \"Harbor Night\", ", with: "")))
        XCTAssertThrowsError(try RaycastTheme.parse("{" + String(repeating: " ", count: RaycastTheme.maximumBytes) + "}")) {
            XCTAssertEqual($0 as? RaycastTheme.ParseError, .tooLarge)
        }
    }

    func testDerivedPaletteKeepsTextReadable() throws {
        let theme = try RaycastTheme.parse(json)
        let palette = theme.palette
        XCTAssertTrue(palette.isValid)
        XCTAssertEqual(palette.background, "#101418")
        XCTAssertEqual(palette.secondaryBackground, "#0c1014")
        XCTAssertEqual(palette.accent, "#6ca8f0", "blue is the first semantic color with 3:1 contrast")
        XCTAssertGreaterThanOrEqual(try XCTUnwrap(ColorPalette.contrast(palette.secondaryText, palette.background)), 4.5)
        XCTAssertGreaterThanOrEqual(try XCTUnwrap(ColorPalette.contrast(palette.text, palette.selection)), 4.5)
        XCTAssertNotEqual(palette.secondaryText, palette.text, "secondary text is blended toward the background")
    }

    func testBrightSelectionIsSoftenedUntilTextIsReadable() throws {
        var bright = colors
        bright[3] = "#E0E4E8"
        let link = "raycast://theme?name=Fixture%20Glare&appearance=dark&colors=" + bright.map { $0.replacingOccurrences(of: "#", with: "%23") }.joined(separator: ",")
        let palette = try RaycastTheme.parse(link).palette
        XCTAssertNotEqual(palette.selection, "#e0e4e8")
        XCTAssertGreaterThanOrEqual(try XCTUnwrap(ColorPalette.contrast(palette.text, palette.selection)), 4.5)
    }

    func testIdentifierIsAStableSlug() {
        XCTAssertEqual(CustomColorTheme.identifier(for: "Harbor Night"), "custom-harbor-night")
        XCTAssertEqual(CustomColorTheme.identifier(for: "  Rosé — Dusk!! "), "custom-ros-dusk")
        XCTAssertEqual(CustomColorTheme.identifier(for: "✨"), "custom-theme")
    }

    func testSaveSelectsReplacesAndPreservesUnknownFields() throws {
        try Data(#"{"appearance":{"theme":"light","future":1,"customThemes":[{"id":"custom-harbor-night","name":"Old","mode":"dark","note":"keep","palette":{}}]},"other":true}"#.utf8).write(to: url)
        var expected = try JSONDecoder().decode(Preferences.self, from: Data(contentsOf: url)).appearance
        XCTAssertTrue(expected.customThemes.isEmpty, "an entry with an invalid palette is skipped, not fatal")
        let theme = try RaycastTheme.parse(json).customTheme
        try Preferences.saveCustomTheme(theme, select: true, expected: expected, at: url)
        let object = try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as! [String: Any]
        let block = object["appearance"] as! [String: Any]
        let entries = block["customThemes"] as! [[String: Any]]
        XCTAssertEqual(entries.count, 1)
        XCTAssertEqual(entries[0]["name"] as? String, "Harbor Night")
        XCTAssertEqual(entries[0]["note"] as? String, "keep", "unknown fields inside a replaced entry survive")
        XCTAssertEqual(block["colorTheme"] as? String, "custom-harbor-night")
        XCTAssertEqual(block["future"] as? Int, 1)
        XCTAssertEqual(object["other"] as? Bool, true)
        expected = try JSONDecoder().decode(Preferences.self, from: Data(contentsOf: url)).appearance
        XCTAssertEqual(expected.customThemes, [theme])
        XCTAssertEqual(expected.resolvedColorTheme.name, "Harbor Night")
        XCTAssertEqual(expected.effectiveMode, .dark)
        XCTAssertEqual(expected.availableColorThemes.last?.id, "custom-harbor-night")
    }

    func testRemoveReturnsToSystemAndStaleSnapshotsAreRejected() throws {
        try Data(#"{"appearance":{}}"#.utf8).write(to: url)
        let empty = try JSONDecoder().decode(Preferences.self, from: Data(contentsOf: url)).appearance
        let theme = try RaycastTheme.parse(json).customTheme
        try Preferences.saveCustomTheme(theme, select: true, expected: empty, at: url)
        let saved = try Data(contentsOf: url)
        XCTAssertThrowsError(try Preferences.removeCustomTheme(theme.id, expected: empty, at: url))
        XCTAssertEqual(try Data(contentsOf: url), saved)
        let current = try JSONDecoder().decode(Preferences.self, from: saved).appearance
        try Preferences.removeCustomTheme(theme.id, expected: current, at: url)
        let after = try JSONDecoder().decode(Preferences.self, from: Data(contentsOf: url)).appearance
        XCTAssertTrue(after.customThemes.isEmpty)
        XCTAssertEqual(after.colorTheme, "system")
    }

    func testImportLimit() throws {
        try Data(#"{"appearance":{}}"#.utf8).write(to: url)
        let base = try RaycastTheme.parse(json).customTheme
        for index in 0..<CustomColorTheme.maximumCount {
            var theme = base
            theme.id = "custom-fixture-\(index)"
            let current = try JSONDecoder().decode(Preferences.self, from: Data(contentsOf: url)).appearance
            try Preferences.saveCustomTheme(theme, select: false, expected: current, at: url)
        }
        let full = try JSONDecoder().decode(Preferences.self, from: Data(contentsOf: url)).appearance
        XCTAssertEqual(full.customThemes.count, CustomColorTheme.maximumCount)
        XCTAssertThrowsError(try Preferences.saveCustomTheme(base, select: false, expected: full, at: url)) {
            XCTAssertTrue($0 is Preferences.CustomThemeLimit)
        }
    }
}
