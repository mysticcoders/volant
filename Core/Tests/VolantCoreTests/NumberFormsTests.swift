import XCTest
@testable import VolantCore

final class NumberFormsTests: XCTestCase {
    private let english = Locale(identifier: "en_US")

    private func card(_ query: String, locale: Locale? = nil) -> [String?] {
        guard let answer = NumberForms.evaluate(query, locale: locale ?? english) else { return [] }
        return [answer.result, answer.resultDetail]
    }

    func testExactFractions() {
        XCTAssertEqual(card("0.25 as fraction"), ["1/4", nil])
        XCTAssertEqual(card("1/3 + 1/6 as fraction"), ["1/2", nil])
        XCTAssertEqual(card("0.1 + 0.2 as fraction"), ["3/10", nil])
        XCTAssertEqual(card("2.75 as fraction"), ["11/4", "2 3/4"])
        XCTAssertEqual(card("-1.5 to fraction"), ["-3/2", "-1 1/2"])
        XCTAssertEqual(card("-0.75 in fraction"), ["-3/4", nil])
        XCTAssertEqual(card("3 as fraction"), ["3", nil])
        XCTAssertEqual(card("0 as fraction"), ["0", nil])
        XCTAssertEqual(card("1/7 + 1/11 as a fraction"), ["18/77", nil])
        XCTAssertEqual(card("0.0001 as fraction"), ["1/10000", nil])
        XCTAssertEqual(card("2,5 as fraction", locale: Locale(identifier: "de_DE")), ["5/2", "2 1/2"])
    }

    /// The closest fraction under the denominator bound, tagged when it is not exact.
    func testApproximateFractions() {
        XCTAssertEqual(card("0.333333 as fraction"), ["1/3", "Approximate"])
        XCTAssertEqual(card("pi as fraction"), ["355/113", "Approximate · 3 16/113"])
        XCTAssertEqual(card("sqrt(2) as fraction"), ["8119/5741", "Approximate · 1 2378/5741"])
        XCTAssertEqual(card("0.00001 as fraction"), ["0", "Approximate"])
        XCTAssertEqual(card("0.123456 as fraction"), ["1229/9955", "Approximate"])
    }

    func testClosestStaysWithinTheBound() throws {
        for value in [0.1234567, 3.14159265, 2.718281828, 0.999999, 1e-3 + 1e-9] {
            let (numerator, denominator) = try XCTUnwrap(NumberForms.closest(value))
            XCTAssertLessThanOrEqual(denominator, NumberForms.maximumDenominator)
            XCTAssertLessThan(abs(Double(numerator) / Double(denominator) - value), 1e-4, "\(value)")
        }
        XCTAssertNil(NumberForms.closest(.infinity))
        XCTAssertNil(NumberForms.closest(.nan))
    }

    func testMixedNumbers() {
        XCTAssertEqual(card("2.75 as mixed number"), ["2 3/4", "11/4"])
        XCTAssertEqual(card("7/2 as a mixed fraction"), ["3 1/2", "7/2"])
        XCTAssertEqual(card("0.5 as mixed number"), ["1/2", nil])
        XCTAssertEqual(card("4 as mixed number"), ["4", nil])
    }

    func testToRoman() {
        XCTAssertEqual(card("2026 in roman"), ["MMXXVI", "Roman numeral"])
        XCTAssertEqual(card("25 to roman numerals"), ["XXV", "Roman numeral"])
        XCTAssertEqual(card("1994 as roman numeral"), ["MCMXCIV", "Roman numeral"])
        XCTAssertEqual(card("3999 in roman"), ["MMMCMXCIX", "Roman numeral"])
        XCTAssertEqual(card("2000 + 26 in roman"), ["MMXXVI", "Roman numeral"])
        XCTAssertEqual(NumberForms.evaluate("25 in roman", locale: english)?.swapQuery, "XXV in decimal")
        for query in ["0 in roman", "4000 in roman", "-5 in roman", "3.5 in roman"] {
            XCTAssertNil(NumberForms.evaluate(query, locale: english), query)
        }
    }

    func testFromRoman() {
        XCTAssertEqual(card("XIV in decimal"), ["14", "Fourteen"])
        XCTAssertEqual(card("roman XIV"), ["14", "Fourteen"])
        XCTAssertEqual(card("roman numeral MMXXVI"), ["2026", "Two thousand twenty-six"])
        XCTAssertEqual(card("mcmxciv to number"), ["1994", "One thousand nine hundred ninety-four"])
        XCTAssertEqual(NumberForms.evaluate("XIV in decimal", locale: english)?.swapQuery, "14 in roman")
        XCTAssertEqual(NumberForms.evaluate("XIV in decimal", locale: english)?.inputDetail, "Roman numeral")
    }

    func testRomanRoundTripsAndRejectsNonStandardForms() {
        for value in 1...3999 {
            guard let numeral = NumberForms.roman(value) else { return XCTFail("\(value)") }
            XCTAssertEqual(NumberForms.integer(numeral), value)
        }
        for numeral in ["IIII", "VX", "IC", "XM", "VV", "MMMM", "IIV", "LL", "", "ABC"] {
            XCTAssertNil(NumberForms.integer(numeral), numeral)
        }
    }

    func testBareWordsAndNumbersStaySearches() {
        for query in ["XIV", "mix", "civic in decimal", "IIII in decimal", "fraction", "as fraction", "apple as fraction",
                      "roman", "roman holiday", "25 roman", "0.25"] {
            XCTAssertNil(NumberForms.evaluate(query, locale: english), query)
        }
    }

    func testAnswersListFractionsOnce() {
        XCTAssertEqual(CalculationAnswer.answers(for: "0.25 as fraction", locale: english).map(\.result), ["1/4"])
        XCTAssertEqual(CalculationAnswer.answers(for: "2026 in roman", locale: english).map(\.result), ["MMXXVI"])
        XCTAssertEqual(CalculationAnswer.answers(for: "1/4", locale: english).map(\.result), ["0.25"])
    }
}
