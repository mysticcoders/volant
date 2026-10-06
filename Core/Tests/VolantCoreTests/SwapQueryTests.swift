import XCTest
@testable import VolantCore

final class SwapQueryTests: XCTestCase {
    private let english = Locale(identifier: "en_US")

    private func swap(_ query: String) -> String? {
        CalculationAnswer.answers(for: query, locale: english).first?.swapQuery
    }

    private func result(_ query: String) -> String? {
        CalculationAnswer.answers(for: query, locale: english).first?.result
    }

    func testUnitConversionsSwapAndRoundTrip() {
        XCTAssertEqual(swap("5 km in mi"), "3.106856 mi in km")
        XCTAssertEqual(result("3.106856 mi in km"), "5 km")
        XCTAssertEqual(swap("100 c in f"), "212 °F in °C")
        XCTAssertEqual(result("212 °F in °C"), "100 °C")
        XCTAssertEqual(swap("5 sq ft in m2"), "0.464515 m² in ft²")
        XCTAssertEqual(result("0.464515 m² in ft²"), "4.999998 ft²")
    }

    func testScreenUnitsSwapKeepingTheirSetting() {
        XCTAssertEqual(swap("2rem in px at 18px"), "36px in rem at 18px")
        XCTAssertEqual(result("36px in rem at 18px"), "2rem")
        XCTAssertEqual(swap("2 inches in px at 72 ppi"), "144px in in at 72 ppi")
        XCTAssertEqual(result("144px in in at 72 ppi"), "2in")
    }

    func testColorsSwapToTheirSourceFormat() {
        XCTAssertEqual(swap("#ff6363"), "rgb(255 99 99) in hex")
        XCTAssertEqual(result("rgb(255 99 99) in hex"), "#ff6363")
        XCTAssertEqual(swap("hsl(120 100% 50%)"), "#00ff00 in hsl")
        XCTAssertNil(swap("red in hex"), "A named color has no way back to its name")
        XCTAssertNil(swap("#ff6363 in hex"), "Same format both ways is not a swap")
    }

    func testCurrencySwapsWithPlainAmounts() throws {
        let rates = CurrencyRates(date: "2026-10-05", perEuro: ["USD": 1.25, "GBP": 0.8, "JPY": 160, "CHF": 0.95, "SEK": 11.5])
        let answer = try XCTUnwrap(CurrencyConverter.evaluate("100 usd in eur", rates: rates, locale: english))
        XCTAssertEqual(answer.swapQuery, "80 EUR in USD")
        XCTAssertEqual(CurrencyConverter.evaluate("80 EUR in USD", rates: rates, locale: english)?.result, "$100.00")
    }

    func testArithmeticAndTimeHaveNoSwap() {
        XCTAssertNil(swap("2 + 2"))
        XCTAssertNil(swap("days until 31 Mar"))
    }
}
