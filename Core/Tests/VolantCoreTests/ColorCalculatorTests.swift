import XCTest
@testable import VolantCore

final class ColorCalculatorTests: XCTestCase {
    private func card(_ query: String) -> [String?] {
        guard let answer = ColorCalculator.evaluate(query) else { return [] }
        return [answer.result, answer.resultDetail, answer.copyText]
    }

    private func convert(_ query: String) -> String? { ColorCalculator.evaluate(query)?.result }

    func testHexAnswersInRGBTaggedWithHSL() throws {
        XCTAssertEqual(card("#ff6363"), ["rgb(255 99 99)", "hsl(0 100% 69.4%)", "rgb(255 99 99)"])
        XCTAssertEqual(convert("#F63"), "rgb(255 102 51)")
        XCTAssertEqual(convert("#ff636380"), "rgb(255 99 99 / 0.502)")
        XCTAssertEqual(convert("#f638"), "rgb(255 102 51 / 0.533)")
        let swatch = try XCTUnwrap(ColorCalculator.evaluate("#ff6363")?.swatch)
        XCTAssertEqual(swatch.red, 1, accuracy: 1e-9)
        XCTAssertEqual(swatch.green, 99.0 / 255, accuracy: 1e-9)
        XCTAssertEqual(swatch.alpha, 1)
    }

    func testOtherFormatsAnswerInHex() {
        XCTAssertEqual(card("rgb(255, 99, 99)"), ["#ff6363", "hsl(0 100% 69.4%)", "#ff6363"])
        XCTAssertEqual(convert("rgba(255, 99, 99, 0.5)"), "#ff636380")
        XCTAssertEqual(convert("rgb(100% 0% 0% / 50%)"), "#ff000080")
        XCTAssertEqual(card("hsl(120 100% 50%)"), ["#00ff00", "rgb(0 255 0)", "#00ff00"])
        XCTAssertEqual(convert("hsla(240, 100%, 50%, 1)"), "#0000ff")
        XCTAssertEqual(convert("hsl(0.5turn 100% 50%)"), "#00ffff")
        XCTAssertEqual(convert("hwb(0 0% 0%)"), "#ff0000")
        XCTAssertEqual(convert("hwb(0 60% 60%)"), "#808080")
    }

    /// Reference values from the CSS Color 4 specification's worked examples for sRGB red and white.
    func testPerceptualFormatsMatchTheSpecification() throws {
        XCTAssertEqual(convert("#ff0000 in lab"), "lab(54.29% 80.8 69.89)")
        let lch = try XCTUnwrap(convert("#ff0000 in lch"))
        XCTAssertTrue(lch.hasPrefix("lch(54.29% 106.84 40.8"), lch)
        XCTAssertEqual(convert("#ff0000 in oklab"), "oklab(62.8% 0.2249 0.1258)")
        XCTAssertEqual(convert("#ff0000 in oklch"), "oklch(62.8% 0.2577 29.23)")
        XCTAssertEqual(convert("#ffffff in lab"), "lab(100% 0 0)")
        XCTAssertEqual(convert("#ffffff in oklch"), "oklch(100% 0 0)")
        XCTAssertEqual(convert("#000 in oklch"), "oklch(0% 0 0)")
    }

    func testRoundTripsThroughEveryFormat() {
        for format in ["rgb", "hsl", "hwb", "lab", "lch", "oklab", "oklch"] {
            guard let converted = convert("#3a7bd5 in \(format)") else { return XCTFail(format) }
            XCTAssertEqual(convert("\(converted) in hex"), "#3a7bd5", format)
        }
        XCTAssertEqual(convert("oklch(62.8% 0.2577 29.23)"), "#ff0000")
        XCTAssertEqual(convert("lab(54.29 80.8 69.89)"), "#ff0000")
    }

    func testTargetsAndSpellings() {
        XCTAssertEqual(convert("#FF6363 to HSL"), "hsl(0 100% 69.4%)")
        XCTAssertEqual(convert("#ff6363 as rgba"), "rgb(255 99 99)")
        XCTAssertEqual(convert("RGB(255 99 99) in hwb"), "hwb(0 38.8% 0%)")
        XCTAssertEqual(ColorCalculator.evaluate("#ff6363 in hex")?.resultDetail, "rgb(255 99 99)")
    }

    func testColorsOutsideSRGBAreClampedAndTagged() throws {
        let vivid = try XCTUnwrap(ColorCalculator.evaluate("oklch(70% 0.4 145)"))
        XCTAssertEqual(vivid.resultDetail?.hasPrefix("Outside sRGB · "), true)
        XCTAssertTrue(vivid.result.hasPrefix("#"))
        XCTAssertEqual(convert("oklch(70% 0.4 145) in oklch"), "oklch(70% 0.4 145)")
        let swatch = try XCTUnwrap(vivid.swatch)
        XCTAssertTrue([swatch.red, swatch.green, swatch.blue].allSatisfy { (0...1).contains($0) })
    }

    func testNeverAnswersOrdinaryText() {
        for query in ["ff6363", "#", "#ff", "#gg0000", "#ff63633", "red", "rgb", "rgb()", "rgb(1, 2)", "rgb(1 2 3 4 5)",
                      "hsl(red 100% 50%)", "rgb(1 2 3) in cmyk", "rgb(1 2 3 / 2)", "Safari", "#hashtag", "lab(1px 2 3)"] {
            XCTAssertNil(ColorCalculator.evaluate(query), query)
        }
    }

    func testCardOrderAndNoArithmeticClash() {
        let answers = CalculationAnswer.answers(for: "rgb(255, 99, 99)", locale: Locale(identifier: "en_US"))
        XCTAssertEqual(answers.map(\.result), ["#ff6363"])
    }
}
