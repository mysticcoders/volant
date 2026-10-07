import XCTest
@testable import VolantCore

final class MoneyCalculatorTests: XCTestCase {
    private let english = Locale(identifier: "en_US")

    private func card(_ query: String, locale: Locale? = nil) -> [String?] {
        guard let answer = MoneyCalculator.evaluate(query, rates: nil, world: nil, crypto: nil, locale: locale ?? english) else { return [] }
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

    private let rates = CurrencyRates(date: "2026-10-05", perEuro: ["USD": 1.25, "GBP": 0.8, "JPY": 160])
    private let now = ISO8601DateFormatter().date(from: "2026-10-06T10:00:00Z")!

    private func mixed(_ query: String, crypto: CryptoPrices? = nil, world: WorldRates? = nil, locale: Locale? = nil) -> [String?] {
        let paris = TimeZone(identifier: "Europe/Paris")!
        guard let answer = MoneyCalculator.evaluate(query, rates: rates, world: world, crypto: crypto, now: now, zone: paris, locale: locale ?? english)
        else { return [] }
        return [answer.result, answer.inputDetail, answer.resultDetail]
    }

    func testMixedCurrenciesConvertBeforeTheArithmetic() {
        XCTAssertEqual(mixed("10 usd + 5 eur in usd"), ["$16.25", "1 EUR = 1.25 USD", "ECB rates · Oct 5"])
        XCTAssertEqual(mixed("$20 + €15"), ["$38.75", "1 EUR = 1.25 USD", "ECB rates · Oct 5"])
        XCTAssertEqual(mixed("£40 - $10 in eur"), ["€42.00", "1 GBP = 1.25 EUR · 1 USD = 0.8 EUR", "ECB rates · Oct 5"])
        XCTAssertEqual(mixed("$20 + $15 in eur"), ["€28.00", "1 USD = 0.8 EUR", "ECB rates · Oct 5"])
        XCTAssertEqual(mixed("10% off $100 + €20 in gbp").first, "£73.60")
        XCTAssertEqual(mixed("20 € + 10 $", locale: Locale(identifier: "de_DE")).first, "28,00 €")
    }

    func testMixedCurrenciesNeedRatesAndKeepOneCurrencyArithmeticRateFree() {
        XCTAssertNil(MoneyCalculator.evaluate("10 usd + 5 eur in usd", rates: nil, world: nil, crypto: nil, locale: english))
        XCTAssertNil(MoneyCalculator.evaluate("$20 + $15 in eur", rates: nil, world: nil, crypto: nil, locale: english))
        XCTAssertEqual(mixed("€50 + €20"), ["€70.00", nil, nil])
        XCTAssertEqual(mixed("$20 + $15 in usd"), ["$35.00", nil, nil])
        XCTAssertEqual(mixed("$100 in eur"), [], "a plain conversion is CurrencyConverter's card")
        XCTAssertEqual(mixed("$20 * €3"), [])
        XCTAssertEqual(mixed("10 usd + 5 chf"), [], "a currency without a rate gives no answer")
    }

    func testMixedAmountsWithACoinUseCoinGeckoPrices() {
        let fetched = ISO8601DateFormatter().date(from: "2026-10-06T09:30:00Z")!
        let crypto = CryptoPrices(fetchedAt: fetched, euros: ["BTC": 100_000])
        XCTAssertEqual(mixed("0.01 btc + $100 in eur", crypto: crypto),
                       ["€1,080.00", "1 BTC = 100,000 EUR · 1 USD = 0.8 EUR", "CoinGecko · 11:30 AM"])
        XCTAssertEqual(mixed("0.01 btc + $100 in eur"), [])
    }

    func testPayForTime() {
        XCTAssertEqual(card("2 hours * $40"), ["$80.00", nil, "$80.00"])
        XCTAssertEqual(card("$5/hr * 40").first, "$200.00")
        XCTAssertEqual(card("$45/hour * 37.5 hours").first, "$1,687.50")
        XCTAssertEqual(card("$45 per hour x 2h 30m").first, "$112.50")
        XCTAssertEqual(card("90 min × €30/h").first, "€45.00")
        XCTAssertEqual(card("$200/day * 5").first, "$1,000.00")
        XCTAssertEqual(card("$200/day * 3 days").first, "$600.00")
        XCTAssertEqual(card("$3000/month * 6 months").first, "$18,000.00")
        XCTAssertEqual(MoneyCalculator.evaluate("$45/hour * 37.5 hours", rates: nil, world: nil, crypto: nil, locale: english)?.inputDetail,
                       "37.5 hours at $45.00/hour")
    }

    func testPayForTimeNeverGuessesADaysLength() {
        XCTAssertEqual(card("$200/day * 10 hours"), [])
        XCTAssertEqual(card("$45/hour * 2 days"), [])
        XCTAssertEqual(card("$40 * 2 days"), [])
        XCTAssertEqual(card("$5/hr * $40"), [])
    }

    func testCurrenciesOutsideTheECBWorkAlone() {
        XCTAssertEqual(card("100 aed + 50 aed").first, "AED 150.00")
        XCTAssertEqual(card("TWD 500 * 2").first, "NT$1,000.00")
        XCTAssertEqual(card("18% tip on 1200 php").first, "₱1,416.00")
        XCTAssertEqual(card("5 CUP + 2 CUP").first, "CUP 7.00", "word-like codes read in capitals")
        XCTAssertEqual(card("5 cup + 2 cup"), [], "and stay kitchen measures otherwise")
        XCTAssertEqual(card("5 kgs + 3 kgs"), [])
        XCTAssertEqual(card("top 5 + 3"), [])
    }

    func testMixedCurrenciesUseExchangeRateAPIWhenTheECBLacksOne() {
        let updated = ISO8601DateFormatter().date(from: "2026-10-06T00:00:00Z")!
        let world = WorldRates(updated: updated, perEuro: ["USD": 1.2, "AED": 4.4, "GBP": 0.85])
        XCTAssertEqual(mixed("100 aed + $20 in usd", world: world),
                       ["$47.27", "1 AED = 0.27273 USD", "Rates By Exchange Rate API · Oct 6"])
        XCTAssertEqual(mixed("100 aed + $20 in usd"), [], "the ECB alone cannot price AED")
        XCTAssertEqual(mixed("$20 + €15", world: world).first, "$38.75", "ECB still prices what it covers")
    }
}
