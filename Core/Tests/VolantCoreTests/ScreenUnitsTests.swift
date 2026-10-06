import XCTest
@testable import VolantCore

final class ScreenUnitsTests: XCTestCase {
    private let english = Locale(identifier: "en_US")

    private func card(_ query: String) -> [String?] {
        guard let answer = ScreenUnits.evaluate(query, locale: english) else { return [] }
        return [answer.result, answer.inputDetail, answer.copyText]
    }

    func testRemAndEmUseSixteenPixelsUnlessSet() {
        XCTAssertEqual(card("2rem in px"), ["32px", "1rem = 16px", "32px"])
        XCTAssertEqual(card("32px in rem"), ["2rem", "1rem = 16px", "2rem"])
        XCTAssertEqual(card("1.5 em to px").first, "24px")
        XCTAssertEqual(card("1.5rem in px at 18px"), ["27px", "1rem = 18px", "27px"])
        XCTAssertEqual(card("27px in rem at 18px").first, "1.5rem")
        XCTAssertEqual(card("13px in rem").first, "0.8125rem")
    }

    func testCSSPhysicalRatios() {
        XCTAssertEqual(card("1in in px"), ["96px", "96px per inch", "96px"])
        XCTAssertEqual(card("12pt in px").first, "16px")
        XCTAssertEqual(card("16px in pt").first, "12pt")
        XCTAssertEqual(card("1pc in pt").first, "12pt")
        XCTAssertEqual(card("2.54 cm in px").first, "96px")
        XCTAssertEqual(card("100px in mm").first, "26.4583mm")
        XCTAssertEqual(card("1 pt in rem").first, "0.0833rem")
    }

    func testPixelsPerInchForPrintAndDesign() {
        XCTAssertEqual(card("2 inches in px at 72 ppi"), ["144px", "72 ppi", "144px"])
        XCTAssertEqual(card("1200px in in at 300 dpi").first, "4in")
        XCTAssertEqual(card("12pt in px at 72 ppi").first, "12px")
        XCTAssertEqual(card("10 cm as px at 300 dpi").first, "1181.1024px")
    }

    func testLeavesOtherUnitsAndMalformedInputAlone() {
        for query in ["1 pt in ml", "5 in in cm", "2 kg in px", "2rem in rem", "2rem in px at 0 ppi", "2px in rem at 18 ppx",
                      "2rem in px at 18pt", "2 px in px", "rem in px", "px", "1in in px at 72px", "Safari"] {
            XCTAssertNil(ScreenUnits.evaluate(query, locale: english), query)
        }
        XCTAssertEqual(UnitConverter.convert("1 pt in ml", locale: english)?.toSymbol, "mL")
    }

    func testCardOrderLeavesPintsToTheUnitConverter() {
        XCTAssertEqual(CalculationAnswer.answers(for: "12pt in px", locale: english).map(\.result), ["16px"])
        XCTAssertEqual(CalculationAnswer.answers(for: "1 pt in ml", locale: english).count, 1)
    }
}
