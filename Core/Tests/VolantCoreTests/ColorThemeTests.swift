import XCTest

@testable import VolantCore

/// Color themes are stored by identifier in the appearance block and must keep text readable.
final class ColorThemeTests: XCTestCase {
    private var url: URL!

    override func setUpWithError() throws {
        url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".json")
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: url)
    }

    func testDefaultIsSystemAndUnknownFallsBack() throws {
        let empty = try JSONDecoder().decode(Preferences.self, from: Data("{}".utf8))
        XCTAssertEqual(empty.appearance.colorTheme, "system")
        XCTAssertNil(empty.appearance.resolvedColorTheme.palette)
        XCTAssertNil(empty.appearance.resolvedColorTheme.accent, "System uses the macOS accent color")
        let unknown = try JSONDecoder().decode(Preferences.self, from: Data(#"{"appearance":{"colorTheme":"sepia"}}"#.utf8))
        XCTAssertEqual(unknown.appearance.resolvedColorTheme.id, "system")
        let wrongType = try JSONDecoder().decode(Preferences.self, from: Data(#"{"appearance":{"colorTheme":7,"scale":1.2}}"#.utf8))
        XCTAssertEqual(wrongType.appearance.colorTheme, "system")
        XCTAssertEqual(wrongType.appearance.scale, 1.2)
    }

    func testUpdateWritesColorThemeAndKeepsUnknownFields() throws {
        try Data(#"{"appearance":{"theme":"light","future":1},"other":true}"#.utf8).write(to: url)
        let expected = try JSONDecoder().decode(Preferences.self, from: Data(contentsOf: url)).appearance
        var updated = expected
        updated.colorTheme = "catppuccin-mocha"
        try Preferences.updateAppearance(updated, expected: expected, at: url)
        let object = try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as! [String: Any]
        let block = object["appearance"] as! [String: Any]
        XCTAssertEqual(block["colorTheme"] as? String, "catppuccin-mocha")
        XCTAssertEqual(block["theme"] as? String, "light")
        XCTAssertEqual(block["future"] as? Int, 1)
        XCTAssertEqual(object["other"] as? Bool, true)
        let reloaded = try JSONDecoder().decode(Preferences.self, from: Data(contentsOf: url)).appearance
        XCTAssertEqual(reloaded, updated)
    }

    func testStaleColorThemeSnapshotIsRejected() throws {
        try Data(#"{"appearance":{"colorTheme":"nord"}}"#.utf8).write(to: url)
        let saved = try Data(contentsOf: url)
        XCTAssertThrowsError(try Preferences.updateAppearance(Appearance(colorTheme: "dracula"), expected: Appearance(), at: url))
        XCTAssertEqual(try Data(contentsOf: url), saved)
    }

    func testNamedThemeModeOverridesAppearanceSetting() {
        XCTAssertNil(Appearance(theme: .system).effectiveMode)
        XCTAssertEqual(Appearance(theme: .light).effectiveMode, .light)
        XCTAssertEqual(Appearance(theme: .light, colorTheme: "catppuccin-mocha").effectiveMode, .dark)
        XCTAssertEqual(Appearance(theme: .dark, colorTheme: "catppuccin-latte").effectiveMode, .light)
        XCTAssertEqual(Appearance(theme: .dark, colorTheme: "volant").effectiveMode, .dark, "Volant follows the setting")
        XCTAssertNil(Appearance(theme: .system, colorTheme: "volant").effectiveMode)
    }

    func testCatalogIsUniqueAndWellFormed() {
        let ids = ColorTheme.catalog.map(\.id)
        XCTAssertEqual(Set(ids).count, ids.count)
        XCTAssertEqual(ids.first, ColorTheme.systemID)
        for theme in ColorTheme.catalog {
            if let palette = theme.palette {
                XCTAssertTrue(palette.isValid, theme.id)
                XCTAssertNotNil(theme.mode, "\(theme.id) palettes decide their own appearance")
            } else {
                XCTAssertNil(theme.mode, theme.id)
            }
        }
        for id in ["catppuccin-latte", "catppuccin-frappe", "catppuccin-macchiato", "catppuccin-mocha", "nord", "dracula",
                   "gruvbox-dark", "gruvbox-light", "solarized-dark", "solarized-light", "tokyo-night", "rose-pine",
                   "rose-pine-dawn", "one-dark", "volant"] {
            XCTAssertEqual(ColorTheme.named(id).id, id)
        }
    }

    /// Text meets WCAG AA (4.5:1) on the background and the selected row; secondary text meets AA on
    /// the background and 3:1 on selection; the accent, used for icons and focus, meets 3:1.
    func testPaletteContrast() throws {
        for theme in ColorTheme.catalog {
            guard let p = theme.palette else { continue }
            let checks: [(String, String, String, Double)] = [
                ("text/background", p.text, p.background, 4.5),
                ("text/secondaryBackground", p.text, p.secondaryBackground, 4.5),
                ("text/selection", p.text, p.selection, 4.5),
                ("secondaryText/background", p.secondaryText, p.background, 4.5),
                ("secondaryText/selection", p.secondaryText, p.selection, 3.0),
                ("accent/background", p.accent, p.background, 3.0)
            ]
            for (name, foreground, background, minimum) in checks {
                let ratio = try XCTUnwrap(ColorPalette.contrast(foreground, background))
                XCTAssertGreaterThanOrEqual(ratio, minimum, "\(theme.id) \(name) is \(String(format: "%.2f", ratio)):1")
            }
        }
        for theme in ColorTheme.catalog {
            guard let accent = theme.accent else { continue }
            XCTAssertGreaterThanOrEqual(try XCTUnwrap(ColorPalette.contrast(accent.light, "#ffffff")), 3.0, theme.id)
            XCTAssertGreaterThanOrEqual(try XCTUnwrap(ColorPalette.contrast(accent.dark, "#1e1e1e")), 3.0, theme.id)
        }
    }

    func testContrastMatchesReferenceValues() throws {
        XCTAssertEqual(try XCTUnwrap(ColorPalette.contrast("#000000", "#ffffff")), 21, accuracy: 0.001)
        XCTAssertEqual(try XCTUnwrap(ColorPalette.contrast("#777777", "#ffffff")), 4.48, accuracy: 0.01)
        XCTAssertNil(ColorPalette.contrast("#12345", "#ffffff"))
        XCTAssertNil(ColorPalette.components("zzzzzz"))
    }
}
