import XCTest

@testable import VolantCore

final class CalculatorTests: XCTestCase {
    private static let english = Locale(identifier: "en_US")
    private static let german = Locale(identifier: "de_DE")

    func testPrecedence() {
        XCTAssertEqual(Calculator.evaluate("2 + 3 * 4", locale: Self.english), 14)
        XCTAssertEqual(Calculator.evaluate("(2 + 3) * 4", locale: Self.english), 20)
        XCTAssertEqual(Calculator.evaluate("2 ^ 3 ^ 2", locale: Self.english), 512)
    }

    func testUnaryMinusAndFunctions() {
        XCTAssertEqual(Calculator.evaluate("-3 + 5", locale: Self.english), 2)
        XCTAssertEqual(Calculator.evaluate("sqrt(16) + abs(-2)", locale: Self.english), 6)
        XCTAssertEqual(Calculator.evaluate("round(2.5) * 2", locale: Self.english), 6)
    }

    func testUnaryMinusBindsLooserThanExponent() {
        XCTAssertEqual(Calculator.evaluate("-2^2", locale: Self.english), -4)
        XCTAssertEqual(Calculator.evaluate("(-2)^2", locale: Self.english), 4)
        XCTAssertEqual(Calculator.evaluate("2^-1", locale: Self.english), 0.5)
        XCTAssertEqual(Calculator.evaluate("2 * -3", locale: Self.english), -6)
        XCTAssertEqual(Calculator.evaluate("-2 * 3", locale: Self.english), -6)
        XCTAssertEqual(Calculator.evaluate("--2", locale: Self.english), 2)
        XCTAssertEqual(Calculator.evaluate("10 - -3", locale: Self.english), 13)
        XCTAssertEqual(Calculator.evaluate("-(2 + 3)", locale: Self.english), -5)
        XCTAssertEqual(Calculator.evaluate("2 ^ -2 ^ 2", locale: Self.english), 0.0625)
    }

    func testRemainderFunctionsAndConstants() {
        XCTAssertEqual(Calculator.evaluate("10 mod 3", locale: Self.english), 1)
        XCTAssertEqual(Calculator.evaluate("-7 mod 3", locale: Self.english), -1)
        XCTAssertEqual(Calculator.evaluate("2 + 10 MOD 4 * 3", locale: Self.english), 8)
        XCTAssertNil(Calculator.evaluate("5 mod 0", locale: Self.english))
        XCTAssertEqual(Calculator.evaluate("floor(2.7) + ceil(2.1)", locale: Self.english), 5)
        XCTAssertEqual(Calculator.evaluate("floor(-2.5)", locale: Self.english), -3)
        XCTAssertEqual(Calculator.evaluate("round(-2.5)", locale: Self.english), -3)
        XCTAssertEqual(Calculator.evaluate("sqrt(abs(-16))", locale: Self.english), 4)
        XCTAssertEqual(Calculator.evaluate("SQRT(9)", locale: Self.english), 3)
        XCTAssertEqual(try XCTUnwrap(Calculator.evaluate("pi", locale: Self.english)), Double.pi, accuracy: 1e-12)
        XCTAssertEqual(try XCTUnwrap(Calculator.evaluate("2 * pi", locale: Self.english)), 2 * Double.pi, accuracy: 1e-12)
        XCTAssertEqual(try XCTUnwrap(Calculator.evaluate("e ^ 2", locale: Self.english)), M_E * M_E, accuracy: 1e-12)
        XCTAssertEqual(Calculator.evaluate("  ( 1 + 2 )*3 ", locale: Self.english), 9)
        XCTAssertEqual(Calculator.evaluate("0.5 + .25", locale: Self.english), 0.75)
    }

    func testPercentagesReadAsWritten() throws {
        XCTAssertEqual(try XCTUnwrap(Calculator.evaluate("52% of 900", locale: Self.english)), 468, accuracy: 1e-9)
        XCTAssertEqual(try XCTUnwrap(Calculator.evaluate("20% off 80", locale: Self.english)), 64, accuracy: 1e-9)
        XCTAssertEqual(try XCTUnwrap(Calculator.evaluate("15% tip on 42", locale: Self.english)), 48.3, accuracy: 1e-9)
        XCTAssertEqual(try XCTUnwrap(Calculator.evaluate("15% on 42", locale: Self.english)), 48.3, accuracy: 1e-9)
        XCTAssertEqual(try XCTUnwrap(Calculator.evaluate("19 + 47%", locale: Self.english)), 27.93, accuracy: 1e-9)
        XCTAssertEqual(try XCTUnwrap(Calculator.evaluate("100 - 10%", locale: Self.english)), 90, accuracy: 1e-9)
        XCTAssertEqual(try XCTUnwrap(Calculator.evaluate("100 - 10% - 10%", locale: Self.english)), 81, accuracy: 1e-9)
        XCTAssertEqual(try XCTUnwrap(Calculator.evaluate("100 + -10%", locale: Self.english)), 90, accuracy: 1e-9)
        XCTAssertEqual(try XCTUnwrap(Calculator.evaluate("200 * 15%", locale: Self.english)), 30, accuracy: 1e-9)
        XCTAssertEqual(try XCTUnwrap(Calculator.evaluate("30 / 50%", locale: Self.english)), 60, accuracy: 1e-9)
        XCTAssertEqual(try XCTUnwrap(Calculator.evaluate("50%", locale: Self.english)), 0.5, accuracy: 1e-9)
        XCTAssertEqual(try XCTUnwrap(Calculator.evaluate("(10 + 5)% of 200", locale: Self.english)), 30, accuracy: 1e-9)
        XCTAssertEqual(try XCTUnwrap(Calculator.evaluate("20% of 50 + 10", locale: Self.english)), 20, accuracy: 1e-9)
        XCTAssertEqual(try XCTUnwrap(Calculator.evaluate("10% - 5", locale: Self.english)), -4.9, accuracy: 1e-9)
        XCTAssertEqual(try XCTUnwrap(Calculator.evaluate("12.5% OF 80", locale: Self.english)), 10, accuracy: 1e-9)
    }

    func testPercentWordsNeedAPercentage() {
        for query in ["10 % 3", "52 of 900", "20 off 80", "15 tip on 42", "15% tip 42", "50% of 20%",
                      "%5", "(%5)", "5 +% 3", "10%%", "of 5", "5 of", "20% off"] {
            XCTAssertNil(Calculator.evaluate(query, locale: Self.english), query)
        }
    }

    private func value(_ query: String) throws -> Double { try XCTUnwrap(Calculator.evaluate(query, locale: Self.english), query) }

    func testTrigonometryInRadiansUnlessMarkedDegrees() throws {
        XCTAssertEqual(try value("sin(pi/2)"), 1, accuracy: 1e-12)
        XCTAssertEqual(try value("cos(pi)"), -1, accuracy: 1e-12)
        XCTAssertEqual(try value("sin(90°)"), 1, accuracy: 1e-12)
        XCTAssertEqual(try value("sin 30 deg"), 0.5, accuracy: 1e-12)
        XCTAssertEqual(try value("cos(60 degrees)"), 0.5, accuracy: 1e-12)
        XCTAssertEqual(try value("tan(45°)"), 1, accuracy: 1e-12)
        XCTAssertEqual(try value("cot(45°)"), 1, accuracy: 1e-12)
        XCTAssertEqual(try value("sec(60°)"), 2, accuracy: 1e-12)
        XCTAssertEqual(try value("csc(30°)"), 2, accuracy: 1e-12)
        XCTAssertEqual(try value("asin(1)"), .pi / 2, accuracy: 1e-12)
        XCTAssertEqual(try value("acos(0)"), .pi / 2, accuracy: 1e-12)
        XCTAssertEqual(try value("atan(1) * 4"), .pi, accuracy: 1e-12)
        XCTAssertEqual(try value("sinh(0) + cosh(0) + tanh(0)"), 1, accuracy: 1e-12)
        XCTAssertEqual(try value("asinh(sinh(2))"), 2, accuracy: 1e-12)
        XCTAssertEqual(try value("sin(1 rad)"), Foundation.sin(1), accuracy: 1e-12)
        XCTAssertEqual(Calculator.format(try value("sin(pi)"), locale: Self.english), "0")
    }

    func testLogarithmsRootsAndFactorial() throws {
        XCTAssertEqual(try value("ln(e)"), 1, accuracy: 1e-12)
        XCTAssertEqual(try value("log(1000)"), 3, accuracy: 1e-12)
        XCTAssertEqual(try value("log10 100"), 2, accuracy: 1e-12)
        XCTAssertEqual(try value("log2(1024)"), 10, accuracy: 1e-12)
        XCTAssertEqual(try value("exp(0)"), 1, accuracy: 1e-12)
        XCTAssertEqual(try value("cbrt(27)"), 3, accuracy: 1e-12)
        XCTAssertEqual(try value("cbrt(-8)"), -2, accuracy: 1e-12)
        XCTAssertEqual(try value("5!"), 120)
        XCTAssertEqual(try value("0!"), 1)
        XCTAssertEqual(try value("3! + 1"), 7)
        XCTAssertEqual(try value("-3!"), -6)
        XCTAssertEqual(try value("(2 + 1)!"), 6)
        XCTAssertEqual(try value("2^3!"), 64)
        XCTAssertEqual(try value("20!"), 2_432_902_008_176_640_000)
    }

    func testEverydayPhrasings() throws {
        XCTAssertEqual(try value("square root of 625"), 25)
        XCTAssertEqual(try value("Square Root Of 2") , 2.squareRoot(), accuracy: 1e-12)
        XCTAssertEqual(try value("cube root of 27"), 3, accuracy: 1e-12)
        XCTAssertEqual(try value("2 power 10"), 1024)
        XCTAssertEqual(try value("4 power 6"), 4096)
        XCTAssertEqual(try value("2 to the power of 10"), 1024)
        XCTAssertEqual(try value("5 squared"), 25)
        XCTAssertEqual(try value("3 cubed + 1"), 28)
        XCTAssertEqual(try value("5 factorial"), 120)
    }

    func testFunctionsBindToTheValueRightAfterThem() throws {
        XCTAssertEqual(try value("sqrt 16 + 9"), 13)
        XCTAssertEqual(try value("sqrt(16 + 9)"), 5)
        XCTAssertEqual(try value("2 * sqrt 16"), 8)
        XCTAssertEqual(try value("abs -3 + 1"), 4)
        XCTAssertEqual(try value("sqrt sqrt 16"), 2)
        XCTAssertEqual(try value("floor(2.7) + ceil(2.1)"), 5)
    }

    func testMultiArgumentFunctions() throws {
        XCTAssertEqual(try value("max(3, 7, 5)"), 7)
        XCTAssertEqual(try value("min(3,7)"), 3)
        XCTAssertEqual(try value("max(1, 500)"), 500)
        XCTAssertEqual(try value("max(1,500, 2)"), 1500, "1,500 is grouping when it can be")
        XCTAssertEqual(try value("atan2(1, 1)"), .pi / 4, accuracy: 1e-12)
        XCTAssertEqual(try value("hypot(3, 4)"), 5)
        XCTAssertEqual(try value("pow(2, 10)"), 1024)
        XCTAssertEqual(try value("log(8, 2)"), 3, accuracy: 1e-12)
        XCTAssertEqual(try value("log(100)"), 2, accuracy: 1e-12)
        XCTAssertEqual(try value("round(3.14159, 2)"), 3.14)
        XCTAssertEqual(try value("round(1234, -2)"), 1200)
        XCTAssertEqual(try value("gcd(12, 18)"), 6)
        XCTAssertEqual(try value("lcm(4, 6)"), 12)
        XCTAssertEqual(try value("nCr(10, 3)"), 120)
        XCTAssertEqual(try value("choose(52, 5)"), 2_598_960)
        XCTAssertEqual(try value("nPr(10, 3)"), 720)
        XCTAssertEqual(try value("max(2, -3) * min(4; 6)"), 8)
        XCTAssertEqual(try value("max(1 + 2, 2 * 2)"), 4)
        XCTAssertEqual(try value("sqrt(max(9, 16))"), 4)
        XCTAssertEqual(try value("2 * hypot(3, 4) + 1"), 11)
        XCTAssertEqual(Calculator.evaluate("max(2,5; 7)", locale: Self.german), 7)
    }

    func testMultiArgumentFunctionsRejectBadArguments() {
        for query in ["max(5)", "max(1,500)", "max()", "max(1,)", "max(,1)", "atan2(1)", "hypot(1, 2, 3)", "gcd(1.5, 3)",
                      "nCr(3, 5)", "nCr(-1, 0)", "log(8, 1)", "round(1, 1.5)", "sqrt(4, 9)", "(1, 2)", "1, 2", "max 1, 2"] {
            XCTAssertNil(Calculator.evaluate(query, locale: Self.english), query)
        }
    }

    func testNonRealResultsGiveNoAnswer() {
        for query in ["sqrt(-1)", "asin(2)", "ln(0)", "log(-1)", "acosh(0.5)", "(-1)!", "2.5!", "171!", "1e308 * 10", "atanh(1)"] {
            XCTAssertNil(Calculator.evaluate(query, locale: Self.english), query)
        }
    }

    func testRejectsUnknownFunctionsAndMalformedNumbers() {
        for query in ["sine(1)", "foo(2)", "2 pi", "1..2 + 1", "1.2.3", "2 ** 3", "()", "3 +* 4", "sqrt()", "2 $ 3"] {
            XCTAssertNil(Calculator.evaluate(query, locale: Self.english), query)
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

    func testGroupingFollowsTheLocale() {
        XCTAssertEqual(Calculator.evaluate("1,000 + 5", locale: Self.english), 1005)
        XCTAssertEqual(Calculator.evaluate("12,345,678 / 2", locale: Self.english), 6_172_839)
        XCTAssertEqual(Calculator.evaluate("1,234.5 * 2", locale: Self.english), 2469)
        XCTAssertEqual(Calculator.evaluate("2,5 * 2", locale: Self.german), 5)
        XCTAssertEqual(Calculator.evaluate("1.000 + 5", locale: Self.german), 1005)
        XCTAssertEqual(Calculator.evaluate("1.234,5 * 2", locale: Self.german), 2469)
        for query in ["1,5 + 1", "1,00 + 1", "1,0000 + 1", ",5 + 1", "1, 000", "1,000,00"] {
            XCTAssertNil(Calculator.evaluate(query, locale: Self.english), query)
        }
        XCTAssertNil(Calculator.evaluate("1.5 + 1", locale: Self.german))
        XCTAssertEqual(Calculator.format(2.5, locale: Self.german), "2,5")
    }

    func testScientificNotationAndMagnitudes() {
        XCTAssertEqual(Calculator.evaluate("1e3 * 2", locale: Self.english), 2000)
        XCTAssertEqual(Calculator.evaluate("2.5E-3 * 1000", locale: Self.english), 2.5)
        XCTAssertEqual(Calculator.evaluate("1e+2", locale: Self.english), 100)
        XCTAssertEqual(Calculator.evaluate("10K", locale: Self.english), 10_000)
        XCTAssertEqual(Calculator.evaluate("10k + 500", locale: Self.english), 10_500)
        XCTAssertEqual(Calculator.evaluate("2.5M / 2", locale: Self.english), 1_250_000)
        XCTAssertEqual(Calculator.evaluate("1B", locale: Self.english), 1e9)
        XCTAssertEqual(Calculator.evaluate("2.5 million", locale: Self.english), 2_500_000)
        XCTAssertEqual(Calculator.evaluate("3 thousand + 1 billion", locale: Self.english), 1_000_003_000)
        XCTAssertEqual(Calculator.evaluate("10% of 2K", locale: Self.english), 200)
        for query in ["5m", "5b", "1e", "e3", "10Kg", "million", "2e", "1.5e"] {
            XCTAssertNil(Calculator.evaluate(query, locale: Self.english), query)
        }
    }

    func testRejectsAppNamesAndGarbage() {
        XCTAssertNil(Calculator.evaluate("Safari", locale: Self.english))
        XCTAssertNil(Calculator.evaluate("2 +", locale: Self.english))
        XCTAssertNil(Calculator.evaluate("1 / 0", locale: Self.english))
        XCTAssertNil(Calculator.evaluate("(1 + 2", locale: Self.english))
    }

    func testFormatting() {
        XCTAssertEqual(Calculator.format(42, locale: Self.english), "42")
        XCTAssertEqual(Calculator.format(0.1 + 0.2, locale: Self.english), "0.3")
        XCTAssertEqual(Calculator.format(-12, locale: Self.english), "-12")
        XCTAssertEqual(Calculator.format(1_234_567, locale: Self.english), "1234567")
        XCTAssertEqual(Calculator.format(2.5, locale: Self.english), "2.5")
        XCTAssertEqual(Calculator.format(1.0 / 3, locale: Self.english), "0.3333333333")
        XCTAssertEqual(Calculator.format(.infinity, locale: Self.english), "undefined")
        XCTAssertEqual(Calculator.format(.nan, locale: Self.english), "undefined")
    }
}
