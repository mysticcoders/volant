import XCTest

@testable import VolantCore

final class NumberBasesTests: XCTestCase {
    private static let english = Locale(identifier: "en_US")
    private static let german = Locale(identifier: "de_DE")

    private func card(_ query: String, locale: Locale = english) -> [String?] {
        guard let answer = NumberBases.evaluate(query, locale: locale) else { return [] }
        return [answer.result, answer.resultDetail, answer.inputDetail, answer.copyText, answer.swapQuery]
    }

    func testDecimalToOtherBases() {
        XCTAssertEqual(card("255 in hex"), ["0xFF", "Hexadecimal", "Decimal", "0xFF", "0xFF in decimal"])
        XCTAssertEqual(card("255 to binary"), ["0b11111111", "Binary", "Decimal", "0b11111111", "0b11111111 in decimal"])
        XCTAssertEqual(card("255 as octal"), ["0o377", "Octal", "Decimal", "0o377", "0o377 in decimal"])
        XCTAssertEqual(card("10 in HEXADECIMAL").first, "0xA")
        XCTAssertEqual(card("0 in bin").first, "0b0")
    }

    func testPrefixedLiteralsConvertBetweenBases() {
        XCTAssertEqual(card("0x1F in decimal"), ["31", "Decimal", "Hexadecimal", "31", "31 in hex"])
        XCTAssertEqual(card("0xff in binary"), ["0b11111111", "Binary", "Hexadecimal", "0b11111111", "0b11111111 in hex"])
        XCTAssertEqual(card("0b1010 in hex"), ["0xA", "Hexadecimal", "Binary", "0xA", "0xA in binary"])
        XCTAssertEqual(card("0o17 in dec"), ["15", "Decimal", "Octal", "15", "15 in octal"])
        XCTAssertEqual(card("0X1f in hex"), ["0x1F", "Hexadecimal", "Hexadecimal", "0x1F", nil])
    }

    func testExpressionsConvertTheirValue() {
        XCTAssertEqual(card("2^16 in hex"), ["0x10000", "Hexadecimal", "Decimal", "0x10000", "0x10000 in decimal"])
        XCTAssertEqual(card("0x10 + 1 in decimal"), ["17", "Decimal", "= 17", "17", nil])
        XCTAssertEqual(card("1.000 in hex", locale: Self.german).first, "0x3E8")
    }

    func testNegativesKeepTheirSign() {
        XCTAssertEqual(card("-255 in hex"), ["-0xFF", "Hexadecimal", "Decimal", "-0xFF", "-0xFF in decimal"])
        XCTAssertEqual(card("-0x10 in decimal").first, "-16")
    }

    func testLongBinaryShowsInGroupsButCopiesWhole() {
        XCTAssertEqual(card("4095 in binary").prefix(4), ["0b1111 1111 1111", "Binary", "Decimal", "0b111111111111"])
        XCTAssertEqual(card("256 in binary").first, "0b1 0000 0000")
    }

    func testOnlyWholeExactNumbersConvert() {
        for query in ["1.5 in hex", "pi in hex", "2^60 in hex", "1/3 in binary"] {
            XCTAssertNil(NumberBases.evaluate(query, locale: Self.english), query)
        }
        XCTAssertEqual(card("2^53 in hex").first, "0x20000000000000")
    }

    func testDecimalTargetsNeedAPrefixedLiteral() {
        for query in ["1010 in decimal", "cafe in decimal", "10 in dec", "255 in decimal", "ff in decimal"] {
            XCTAssertNil(NumberBases.evaluate(query, locale: Self.english), query)
        }
    }

    func testWordsAndColorsStaySearchesOrColors() {
        for query in ["red in hex", "#ff6363 in hex", "notes in binary", "5 in in cm", "255 in hexagons", "255 hex"] {
            XCTAssertNil(NumberBases.evaluate(query, locale: Self.english), query)
        }
    }

    func testCalculatorReadsPrefixedLiterals() {
        XCTAssertEqual(Calculator.evaluate("0x1F", locale: Self.english), 31)
        XCTAssertEqual(Calculator.evaluate("0b1010", locale: Self.english), 10)
        XCTAssertEqual(Calculator.evaluate("0o17", locale: Self.english), 15)
        XCTAssertEqual(Calculator.evaluate("0x1F + 0b1010 * 2", locale: Self.english), 51)
        XCTAssertEqual(Calculator.evaluate("-0xff", locale: Self.english), -255)
        XCTAssertEqual(Calculator.evaluate("max(0x10, 0b11)", locale: Self.english), 16)
        XCTAssertEqual(Calculator.evaluate("0.5 + 0", locale: Self.english), 0.5)
        XCTAssertEqual(Calculator.evaluate("10 * 0", locale: Self.english), 0)
        for query in ["0x", "0x1G", "0b102", "0o8", "0b", "0x1F2Z", "0xFFFFFFFFFFFFFFFFF"] {
            XCTAssertNil(Calculator.evaluate(query, locale: Self.english), query)
        }
    }

    func testAnswersListTheConversionCard() {
        let answers = CalculationAnswer.answers(for: "255 in hex", locale: Self.english)
        XCTAssertEqual(answers.map(\.result), ["0xFF"])
        XCTAssertEqual(CalculationAnswer.answers(for: "0x1F", locale: Self.english).map(\.result), ["31"])
    }
}
