import XCTest
@testable import VolantCore

final class NumberDisplayTests: XCTestCase {
    private static let english = Locale(identifier: "en_US")
    private static let german = Locale(identifier: "de_DE")

    private func shown(_ query: String, locale: Locale = english) -> String? {
        Calculator.evaluate(query, locale: locale).map { Calculator.format($0, locale: locale) }
    }

    func testWholeNumbersPrintInFullWhileExact() {
        XCTAssertEqual(shown("2^53"), "9007199254740992")
        XCTAssertEqual(shown("2^50"), "1125899906842624")
        XCTAssertEqual(shown("-2^53"), "-9007199254740992")
        XCTAssertEqual(shown("10^15"), "1000000000000000")
    }

    func testLargeValuesUseScientificNotationWithoutInventedDigits() {
        XCTAssertEqual(shown("2^64"), "1.8446744074e19")
        XCTAssertEqual(shown("100!"), "9.3326215444e157")
        XCTAssertEqual(shown("1e100"), "1e100")
        XCTAssertEqual(shown("-2^70"), "-1.1805916207e21")
        XCTAssertEqual(shown("9.99999999999e20"), "1e21")
    }

    func testTinyValuesUseScientificNotation() {
        XCTAssertEqual(shown("1e-12"), "1e-12")
        XCTAssertEqual(shown("0.0000001"), "1e-7")
        XCTAssertEqual(shown("1.5 / 1000000000"), "1.5e-9")
        XCTAssertEqual(shown("0.000001"), "0.000001")
        XCTAssertEqual(shown("0.0001234"), "0.0001234")
    }

    func testTrigonometryOfMultiplesOfPiReadsAsZero() {
        XCTAssertEqual(shown("sin(pi)"), "0")
        XCTAssertEqual(shown("cos(pi / 2)"), "0")
        XCTAssertEqual(shown("tan(pi)"), "0")
        XCTAssertEqual(shown("sin(90°)"), "1")
    }

    func testScientificResultsReadBackAsTheSameValue() throws {
        for query in ["2^64", "100!", "1e-12", "-2^70"] {
            let english = try XCTUnwrap(shown(query))
            let value = try XCTUnwrap(Calculator.evaluate(query, locale: Self.english))
            let back = try XCTUnwrap(Calculator.evaluate(english, locale: Self.english))
            XCTAssertEqual(back, value, accuracy: abs(value) * 1e-10, query)
            let german = try XCTUnwrap(shown(query, locale: Self.german))
            XCTAssertEqual(try XCTUnwrap(Calculator.evaluate(german, locale: Self.german)), value, accuracy: abs(value) * 1e-10, query)
        }
        XCTAssertEqual(shown("2^64", locale: Self.german), "1,8446744074e19")
    }

    func testCardsTagScientificResultsWithPowersOfTen() {
        func detail(_ query: String) -> String? {
            CalculationAnswer.answers(for: query, locale: Self.english).first?.resultDetail
        }
        XCTAssertEqual(detail("2^64"), "1.8446744074 × 10¹⁹")
        XCTAssertEqual(detail("1e-12"), "1 × 10⁻¹²")
        XCTAssertEqual(detail("100!"), "9.3326215444 × 10¹⁵⁷")
        XCTAssertEqual(detail("2^10"), "One thousand twenty-four")
    }
}
