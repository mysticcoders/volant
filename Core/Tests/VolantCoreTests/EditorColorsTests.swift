import XCTest
@testable import VolantCore

final class EditorColorsTests: XCTestCase {
    /// Every built-in palette and an imported Raycast theme give an editor where prose, dimmed
    /// syntax and code tokens meet WCAG AA on both the page and the code background, and where the
    /// code background and the selection each stay visible against the page and each other.
    func testEditorColorsAreReadableAndDistinctInEveryPalette() throws {
        let imported = try RaycastTheme.parse("raycast://theme?name=Harbor%20Night&appearance=dark&colors=%23101418,%230C1014,%23E8ECF0,%232A3440,%237A8490,%23F06060,%23F09050,%23E8C860,%2370C080,%236CA8F0,%23A890F0,%23E080C8")
        let palettes = ColorTheme.catalog.compactMap { theme in theme.palette.map { (theme.id, $0) } } + [("imported", imported.palette)]
        XCTAssertGreaterThan(palettes.count, 10)
        for (id, palette) in palettes {
            let editor = EditorColors(palette: palette)
            for (name, color) in [("text", editor.text), ("syntax", editor.syntax), ("keyword", editor.keyword),
                                  ("number", editor.number), ("string", editor.string)] {
                for (surface, background) in [("page", palette.background), ("code", editor.code)] {
                    let ratio = try XCTUnwrap(ColorPalette.contrast(color, background))
                    XCTAssertGreaterThanOrEqual(ratio, 4.5, "\(id) \(name) on \(surface) is \(String(format: "%.2f", ratio)):1")
                }
            }
            let steps = [("code/page", editor.code, palette.background), ("code/selection", editor.code, editor.selection),
                         ("selection/page", editor.selection, palette.background)]
            for (name, first, second) in steps {
                XCTAssertGreaterThanOrEqual(try XCTUnwrap(ColorPalette.contrast(first, second)), EditorColors.surfaceStep, "\(id) \(name)")
            }
            XCTAssertEqual(editor.caret, palette.accent, id)
        }
    }

    /// Token colors keep their hue when it is already readable, so themes still look like themselves.
    func testReadableTokensKeepThePaletteHue() throws {
        let mocha = try XCTUnwrap(ColorTheme.named("catppuccin-mocha").palette)
        let editor = EditorColors(palette: mocha)
        XCTAssertEqual(editor.keyword, mocha.purple)
        XCTAssertEqual(editor.string, mocha.green)
        XCTAssertEqual(editor.syntax, mocha.secondaryText)
    }

    /// Blending is linear in sRGB and clamps to the endpoints.
    func testBlend() {
        XCTAssertEqual(ColorPalette.blend("#000000", "#ffffff", 0), "#000000")
        XCTAssertEqual(ColorPalette.blend("#000000", "#ffffff", 1), "#ffffff")
        XCTAssertEqual(ColorPalette.blend("#000000", "#ffffff", 0.5), "#808080")
        XCTAssertEqual(ColorPalette.blend("nope", "#ffffff", 0.5), "nope")
    }
}
