import XCTest

@testable import VolantCore

final class CalculatorTests: XCTestCase {
    func testPrecedence() {
        XCTAssertEqual(Calculator.evaluate("2 + 3 * 4"), 14)
        XCTAssertEqual(Calculator.evaluate("(2 + 3) * 4"), 20)
        XCTAssertEqual(Calculator.evaluate("2 ^ 3 ^ 2"), 512)
    }

    func testUnaryMinusAndFunctions() {
        XCTAssertEqual(Calculator.evaluate("-3 + 5"), 2)
        XCTAssertEqual(Calculator.evaluate("sqrt(16) + abs(-2)"), 6)
        XCTAssertEqual(Calculator.evaluate("round(2.5) * 2"), 6)
    }

    func testUnaryMinusBindsLooserThanExponent() {
        XCTAssertEqual(Calculator.evaluate("-2^2"), -4)
        XCTAssertEqual(Calculator.evaluate("(-2)^2"), 4)
        XCTAssertEqual(Calculator.evaluate("2^-1"), 0.5)
        XCTAssertEqual(Calculator.evaluate("2 * -3"), -6)
        XCTAssertEqual(Calculator.evaluate("-2 * 3"), -6)
        XCTAssertEqual(Calculator.evaluate("--2"), 2)
        XCTAssertEqual(Calculator.evaluate("10 - -3"), 13)
        XCTAssertEqual(Calculator.evaluate("-(2 + 3)"), -5)
        XCTAssertEqual(Calculator.evaluate("2 ^ -2 ^ 2"), 0.0625)
    }

    func testRemainderFunctionsAndConstants() {
        XCTAssertEqual(Calculator.evaluate("10 mod 3"), 1)
        XCTAssertEqual(Calculator.evaluate("-7 mod 3"), -1)
        XCTAssertEqual(Calculator.evaluate("2 + 10 MOD 4 * 3"), 8)
        XCTAssertNil(Calculator.evaluate("5 mod 0"))
        XCTAssertEqual(Calculator.evaluate("floor(2.7) + ceil(2.1)"), 5)
        XCTAssertEqual(Calculator.evaluate("floor(-2.5)"), -3)
        XCTAssertEqual(Calculator.evaluate("round(-2.5)"), -3)
        XCTAssertEqual(Calculator.evaluate("sqrt(abs(-16))"), 4)
        XCTAssertEqual(Calculator.evaluate("SQRT(9)"), 3)
        XCTAssertEqual(try XCTUnwrap(Calculator.evaluate("pi")), Double.pi, accuracy: 1e-12)
        XCTAssertEqual(try XCTUnwrap(Calculator.evaluate("2 * pi")), 2 * Double.pi, accuracy: 1e-12)
        XCTAssertEqual(try XCTUnwrap(Calculator.evaluate("e ^ 2")), M_E * M_E, accuracy: 1e-12)
        XCTAssertEqual(Calculator.evaluate("  ( 1 + 2 )*3 "), 9)
        XCTAssertEqual(Calculator.evaluate("0.5 + .25"), 0.75)
    }

    func testPercentagesReadAsWritten() throws {
        XCTAssertEqual(try XCTUnwrap(Calculator.evaluate("52% of 900")), 468, accuracy: 1e-9)
        XCTAssertEqual(try XCTUnwrap(Calculator.evaluate("20% off 80")), 64, accuracy: 1e-9)
        XCTAssertEqual(try XCTUnwrap(Calculator.evaluate("15% tip on 42")), 48.3, accuracy: 1e-9)
        XCTAssertEqual(try XCTUnwrap(Calculator.evaluate("15% on 42")), 48.3, accuracy: 1e-9)
        XCTAssertEqual(try XCTUnwrap(Calculator.evaluate("19 + 47%")), 27.93, accuracy: 1e-9)
        XCTAssertEqual(try XCTUnwrap(Calculator.evaluate("100 - 10%")), 90, accuracy: 1e-9)
        XCTAssertEqual(try XCTUnwrap(Calculator.evaluate("100 - 10% - 10%")), 81, accuracy: 1e-9)
        XCTAssertEqual(try XCTUnwrap(Calculator.evaluate("100 + -10%")), 90, accuracy: 1e-9)
        XCTAssertEqual(try XCTUnwrap(Calculator.evaluate("200 * 15%")), 30, accuracy: 1e-9)
        XCTAssertEqual(try XCTUnwrap(Calculator.evaluate("30 / 50%")), 60, accuracy: 1e-9)
        XCTAssertEqual(try XCTUnwrap(Calculator.evaluate("50%")), 0.5, accuracy: 1e-9)
        XCTAssertEqual(try XCTUnwrap(Calculator.evaluate("(10 + 5)% of 200")), 30, accuracy: 1e-9)
        XCTAssertEqual(try XCTUnwrap(Calculator.evaluate("20% of 50 + 10")), 20, accuracy: 1e-9)
        XCTAssertEqual(try XCTUnwrap(Calculator.evaluate("10% - 5")), -4.9, accuracy: 1e-9)
        XCTAssertEqual(try XCTUnwrap(Calculator.evaluate("12.5% OF 80")), 10, accuracy: 1e-9)
    }

    func testPercentWordsNeedAPercentage() {
        for query in ["10 % 3", "52 of 900", "20 off 80", "15 tip on 42", "15% tip 42", "50% of 20%",
                      "%5", "(%5)", "5 +% 3", "10%%", "of 5", "5 of", "20% off"] {
            XCTAssertNil(Calculator.evaluate(query), query)
        }
    }

    func testRejectsUnknownFunctionsAndMalformedNumbers() {
        for query in ["sin(1)", "foo(2)", "2 pi", "1..2 + 1", "1.2.3", "2 ** 3", "()", "3 +* 4", "sqrt()", "2 $ 3"] {
            XCTAssertNil(Calculator.evaluate(query), query)
        }
    }

    func testRecognizesOnlyCalculationShapedText() {
        XCTAssertTrue(Calculator.looksNumeric("2 + 2"))
        XCTAssertTrue(Calculator.looksNumeric("pi"))
        XCTAssertTrue(Calculator.looksNumeric("e"))
        XCTAssertFalse(Calculator.looksNumeric("Safari"))
        XCTAssertFalse(Calculator.looksNumeric(""))
        XCTAssertFalse(Calculator.looksNumeric("2 + 2 = 4"))
    }

    func testRejectsAppNamesAndGarbage() {
        XCTAssertNil(Calculator.evaluate("Safari"))
        XCTAssertNil(Calculator.evaluate("2 +"))
        XCTAssertNil(Calculator.evaluate("1 / 0"))
        XCTAssertNil(Calculator.evaluate("(1 + 2"))
    }

    func testFormatting() {
        XCTAssertEqual(Calculator.format(42), "42")
        XCTAssertEqual(Calculator.format(0.1 + 0.2), "0.3")
        XCTAssertEqual(Calculator.format(-12), "-12")
        XCTAssertEqual(Calculator.format(1_234_567), "1234567")
        XCTAssertEqual(Calculator.format(2.5), "2.5")
        XCTAssertEqual(Calculator.format(1.0 / 3), "0.3333333333")
        XCTAssertEqual(Calculator.format(.infinity), "undefined")
        XCTAssertEqual(Calculator.format(.nan), "undefined")
    }
}
