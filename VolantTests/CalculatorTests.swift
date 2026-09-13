import XCTest
@testable import Volant

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

    func testRejectsAppNamesAndGarbage() {
        XCTAssertNil(Calculator.evaluate("Safari"))
        XCTAssertNil(Calculator.evaluate("2 +"))
        XCTAssertNil(Calculator.evaluate("1 / 0"))
        XCTAssertNil(Calculator.evaluate("(1 + 2"))
    }

    func testFormatting() {
        XCTAssertEqual(Calculator.format(42), "42")
        XCTAssertEqual(Calculator.format(0.1 + 0.2), "0.3")
    }
}
