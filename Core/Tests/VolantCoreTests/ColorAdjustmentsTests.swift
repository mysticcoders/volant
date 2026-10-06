import XCTest
@testable import VolantCore

final class ColorAdjustmentsTests: XCTestCase {
    private let english = Locale(identifier: "en_US")

    private func card(_ query: String) -> [String?] {
        guard let answer = ColorAdjustments.evaluate(query, locale: english) else { return [] }
        return [answer.result, answer.resultDetail, answer.inputDetail]
    }

    private func adjust(_ query: String) -> String? { ColorAdjustments.evaluate(query, locale: english)?.result }

    /// Sass reference values: lighten and darken move HSL lightness by absolute points.
    func testLightenAndDarkenMatchSass() {
        XCTAssertEqual(card("#f00 lighten 10%"), ["#ff3333", "rgb(255 51 51)", "Lightness +10% (HSL)"])
        XCTAssertEqual(adjust("#f00 darken 10%"), "#cc0000")
        XCTAssertEqual(adjust("lighten(#f00, 10%)"), "#ff3333")
        XCTAssertEqual(adjust("darken(#800, 20%)"), "#220000")
        XCTAssertEqual(adjust("#f00 lighten by 10%"), "#ff3333")
        XCTAssertEqual(adjust("#F00 LIGHTEN 10%"), "#ff3333")
        XCTAssertEqual(adjust("#fff lighten 10%"), "#ffffff")
        XCTAssertEqual(adjust("#000 darken 50%"), "#000000")
    }

    func testSaturationSteps() {
        XCTAssertEqual(card("#3a7bd5 desaturate 30%"), ["#5e81b1", "rgb(94 129 177)", "Saturation −30% (HSL)"])
        XCTAssertEqual(adjust("saturate(#3a7bd5, 10%)"), "#2e79e1")
        XCTAssertEqual(adjust("#3a7bd5 desaturate 100%"), "#888888")
        XCTAssertEqual(adjust("#808080 saturate 20%"), "#996767")
    }

    func testAdjustmentsAnswerInTheSourceOrRequestedFormat() {
        XCTAssertEqual(adjust("rgb(255 0 0) lighten 10%"), "rgb(255 51 51)")
        XCTAssertEqual(adjust("hsl(0 100% 50%) lighten 10%"), "hsl(0 100% 60%)")
        XCTAssertEqual(adjust("#3a7bd5 saturate 10% in hsl"), "hsl(214.8 74.9% 53.1%)")
        XCTAssertEqual(adjust("#f00 lighten 10% to rgb"), "rgb(255 51 51)")
        XCTAssertEqual(adjust("red lighten 20%"), "#ff6666")
        XCTAssertEqual(adjust("rebecca purple darken 10%"), "#4d2673")
    }

    func testComplementTurnsTheHue() {
        XCTAssertEqual(card("complement of #3a7bd5"), ["#d5943a", "rgb(213 148 58)", "Hue +180°"])
        XCTAssertEqual(adjust("#3a7bd5 complement"), "#d5943a")
        XCTAssertEqual(adjust("complement(red)"), "#00ffff")
        XCTAssertEqual(adjust("complementary of hsl(30 100% 50%)"), "hsl(210 100% 50%)")
        XCTAssertEqual(adjust("complement of #888"), "#888888")
    }

    func testAlphaAndOpacity() throws {
        XCTAssertEqual(card("#3a7bd5 at 50% alpha"), ["#3a7bd580", "rgb(58 123 213 / 0.5)", "Alpha 50%"])
        XCTAssertEqual(adjust("#3a7bd5 with 50% opacity"), "#3a7bd580")
        XCTAssertEqual(adjust("rgb(58 123 213) at 0.25 alpha"), "rgb(58 123 213 / 0.25)")
        XCTAssertEqual(adjust("#3a7bd580 at 100% opacity"), "#3a7bd5")
        XCTAssertNil(adjust("#3a7bd5 at 150% alpha"))
        XCTAssertNil(adjust("#3a7bd5 at 2 alpha"))
        let swatch = try XCTUnwrap(ColorAdjustments.evaluate("#3a7bd5 at 50% alpha", locale: english)?.swatch)
        XCTAssertEqual(swatch.alpha, 0.5, accuracy: 1e-9)
    }

    /// CSS color-mix values: OKLab by default, sRGB on request, percentages filled in or scaled.
    func testMixFollowsColorMix() throws {
        XCTAssertEqual(card("mix(#f00, #00f)"), ["#8c53a2", "rgb(140 83 162)", "50% / 50% in OKLab"])
        XCTAssertEqual(adjust("color-mix(in srgb, #f00, #00f)"), "#800080")
        XCTAssertEqual(card("color-mix(in srgb, #f00 25%, #00f)"), ["#4000bf", "rgb(64 0 191)", "25% / 75% in sRGB"])
        XCTAssertEqual(adjust("color-mix(in srgb, #f00, 75% #00f)"), "#4000bf")
        XCTAssertEqual(adjust("color-mix(in srgb, #f00 60%, #00f 60%)"), "#800080")
        XCTAssertEqual(adjust("color-mix(in srgb, #f00 30%, #00f 30%)"), "#80008099")
        XCTAssertEqual(adjust("mix(rgb(255, 0, 0), blue)"), "rgb(140 83 162)")
        XCTAssertEqual(adjust("color-mix(in srgb-linear, #000, #fff)"), "#bcbcbc")
        XCTAssertEqual(adjust("mix(#fff, #000) in hsl"), "hsl(0 0% 38.9%)")
        XCTAssertEqual(adjust("color-mix(in srgb, #f00, transparent)"), nil)
        XCTAssertEqual(adjust("color-mix(in srgb, #f000, #00f)"), "#0000ff80")
        XCTAssertNil(adjust("mix(#f00)"))
        XCTAssertNil(adjust("mix(#f00, #00f, #0f0)"))
        XCTAssertNil(adjust("color-mix(in hsl, #f00, #00f)"))
        XCTAssertNil(adjust("color-mix(in srgb, #f00 0%, #00f 0%)"))
    }

    /// WCAG 2 ratios checked against published pairs; ratios are floored, never rounded up.
    func testContrastRatio() throws {
        XCTAssertEqual(card("contrast #fff #000"), ["21:1", "Passes AAA", "Text on background"])
        XCTAssertEqual(card("contrast ratio of white and navy"), ["16:1", "Passes AAA", "Text on background"])
        XCTAssertEqual(card("contrast #fff #3a7bd5"), ["4.22:1", "AA for large text only", "Text on background"])
        XCTAssertEqual(adjust("contrast #777 on #fff"), "4.47:1")
        XCTAssertEqual(adjust("contrast #767676 on #fff"), "4.54:1")
        XCTAssertEqual(ColorAdjustments.evaluate("contrast #767676 on #fff", locale: english)?.resultDetail,
                       "Passes AA · AAA for large text")
        XCTAssertEqual(adjust("contrast between rgb(0 0 0) and #fff"), "21:1")
        XCTAssertEqual(adjust("contrast rgb(0, 0, 0), rgb(255, 255, 255)"), "21:1")
        XCTAssertEqual(adjust("contrast light gray vs black"), "14.02:1")
        XCTAssertEqual(ColorAdjustments.evaluate("contrast #ccc #fff", locale: english)?.resultDetail, "Fails AA")
        XCTAssertEqual(adjust("contrast #00000080 on #fff"), "4:1")
        XCTAssertEqual(ColorAdjustments.evaluate("contrast 1,5 on 2", locale: Locale(identifier: "de_DE"))?.result, nil)
        XCTAssertEqual(ColorAdjustments.evaluate("contrast #fff #000", locale: Locale(identifier: "de_DE"))?.result, "21:1")
        XCTAssertEqual(ColorAdjustments.evaluate("contrast #fff #3a7bd5", locale: Locale(identifier: "de_DE"))?.result, "4,22:1")
    }

    func testPlainWordsAndIncompleteInputStaySearches() {
        for query in ["mix", "contrast", "contrast #fff", "contrast apple music", "red", "complement", "lighten",
                      "#f00 lighten", "#f00 lighten 10", "#f00 lighten 120%", "photo lighten 10%", "mix(apple, pear)",
                      "notes at 50% opacity", "#f00 brighten 10%"] {
            XCTAssertNil(ColorAdjustments.evaluate(query, locale: english), query)
        }
    }

    func testAnswersListAdjustmentsOnce() {
        let answers = CalculationAnswer.answers(for: "#f00 lighten 10%", locale: english)
        XCTAssertEqual(answers.map(\.result), ["#ff3333"])
        XCTAssertNil(answers.first?.swapQuery)
        XCTAssertEqual(CalculationAnswer.answers(for: "#ff6363", locale: english).map(\.result), ["rgb(255 99 99)"])
    }
}
