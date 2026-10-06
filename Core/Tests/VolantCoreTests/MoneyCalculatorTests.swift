import XCTest
@testable import VolantCore

final class MoneyCalculatorTests: XCTestCase {
    private let english = Locale(identifier: "en_US")

    private func card(_ query: String, locale: Locale? = nil) -> [String?] {
        guard let answer = MoneyCalculator.evaluate(query, locale: locale ?? english) else { return [] }
        return [answer.result, answer.resultDetail, answer.copyText]
    }

    func testTipsAndDiscountsAnswerInTheCurrency() {
        XCTAssertEqual(card("18% tip on $65"), ["$76.70", "Tip $11.70", "$76.70"])
        XCTAssertEqual(card("18% tip on 65 usd"), ["$76.70", "Tip $11.70", "$76.70"])
        XCTAssertEqual(card("20% off $80"), ["$64.00", nil, "$64.00"])
        XCTAssertEqual(card("20% off 80 usd").first, "$64.00")
        XCTAssertEqual(card("18% of $65").first, "$11.70")
        XCTAssertEqual(card("$65 + 18%").first, "$76.70")
        XCTAssertEqual(card("15% tip on 42 euros").first, "€48.30")
    }

    func testArithmeticOnAmounts() {
        XCTAssertEqual(card("$20 * 3").first, "$60.00")
        XCTAssertEqual(card("$1,200 / 4").first, "$300.00")
        XCTAssertEqual(card("€50 + €20").first, "€70.00")
        XCTAssertEqual(card("£12.50 x 4").first, "£50.00")
        XCTAssertEqual(card("£12.50 × 4").first, "£50.00")
        XCTAssertEqual(card("USD1K - 250").first, "$750.00")
        XCTAssertEqual(card("usd 20 + 5").first, "$25.00")
        XCTAssertEqual(card("¥1000 * 3").first, "¥3,000")
        XCTAssertEqual(card("$5 - $10").first, "-$5.00")
        XCTAssertEqual(card("50 € + 20 €", locale: Locale(identifier: "de_DE")).first, "70,00 €")
    }

    func testNotAnAmountOfOneCurrency() {
        XCTAssertEqual(card("$65"), [])
        XCTAssertEqual(card("100 usd in eur"), [])
        XCTAssertEqual(card("10 usd + 5 eur"), [])
        XCTAssertEqual(card("10 usd + 5 eur in usd"), [])
        XCTAssertEqual(card("$100 / $20"), [])
        XCTAssertEqual(card("$20 * $3"), [])
        XCTAssertEqual(card("20 + 5"), [])
        XCTAssertEqual(card("5 cup + 2 cup"), [])
        XCTAssertEqual(card("max(3, 7) usd"), [])
    }

    func testCalculatorCardsIncludeMoneyOnlyOnce() {
        let paris = TimeZone(identifier: "Europe/Paris")!
        let answers = CalculationAnswer.answers(for: "18% tip on $65", localZone: paris, locale: english)
        XCTAssertEqual(answers.map(\.result), ["$76.70"])
        XCTAssertEqual(CalculationAnswer.answers(for: "15% tip on 42", localZone: paris, locale: english).map(\.result), ["48.3"])
    }
}
