import XCTest
@testable import VolantCore

/// Calculator answers follow the locale they are given: numbers, dates, clocks, durations and
/// currency, with Copy matching what the card shows. Values meant for code or parsed back by
/// Volant (colors, ISO 8601 dates, swap queries) keep their fixed form, and swaps round-trip in
/// each locale. `swift test` has no catalog, so these assert formatting, not translated words.
final class LocaleFormattingTests: XCTestCase {
    private let now = ISO8601DateFormatter().date(from: "2026-10-06T12:15:00Z")!
    private let paris = TimeZone(identifier: "Europe/Paris")!
    private let english = Locale(identifier: "en_US")
    private let german = Locale(identifier: "de_DE")
    private let french = Locale(identifier: "fr_FR")
    private let japanese = Locale(identifier: "ja_JP")

    private func first(_ query: String, _ locale: Locale) -> CalculationAnswer? {
        CalculationAnswer.answers(for: query, now: now, localZone: paris, locale: locale).first
    }

    private func card(_ query: String, _ locale: Locale) -> [String?] {
        guard let answer = first(query, locale) else { return [] }
        return [answer.result, answer.resultDetail, answer.copyText]
    }

    func testNumbersUseTheLocaleSeparators() {
        XCTAssertEqual(card("10 / 4", english).first, "2.5")
        XCTAssertEqual(card("10 / 4", german).first, "2,5")
        XCTAssertEqual(card("10 / 4", french).first, "2,5")
        XCTAssertEqual(card("123 * 1000", german)[1], "123.000")
        XCTAssertEqual(card("123 * 1000", french)[1], "123 000")
        XCTAssertEqual(first("2^64", german)?.result, "1,8446744074e19")
    }

    func testClockTimesFollowTheLocaleClock() {
        XCTAssertEqual(first("3pm est in cet", english)?.result, "9:00 PM CEST")
        XCTAssertEqual(first("3pm est in cet", german)?.result, "21:00 CEST")
        XCTAssertEqual(first("3pm est in cet", french)?.result, "21:00 CEST")
        XCTAssertEqual(first("now", german)?.result, "14:15")
        XCTAssertEqual(first("9am + 90 min", german)?.result, "10:30")
    }

    func testDatesUseTheLocaleDateFormat() {
        XCTAssertEqual(first("in 3 weeks", english)?.result, "Tuesday, October 27")
        XCTAssertEqual(first("in 3 weeks", german)?.result, "Dienstag, 27. Oktober")
        XCTAssertEqual(first("in 3 weeks", french)?.result, "mardi 27 octobre")
        XCTAssertEqual(first("in 3 weeks", japanese)?.result, "10月27日 火曜日")
        XCTAssertEqual(first("days in february 2028", german)?.resultDetail, "Februar 2028")
    }

    func testDurationsUseTheLocaleUnitWords() {
        XCTAssertEqual(card("145 mins to timespan", english).first, "2 hours 25 minutes")
        XCTAssertEqual(card("145 mins to timespan", german).first, "2 Stunden 25 Minuten")
        XCTAssertEqual(card("145 mins to timespan", french).first, "2 heures 25 minutes")
        XCTAssertEqual(card("2h 20min + 55min in hours", german).first, "3,25 Stunden")
        XCTAssertEqual(card("days until Dec 25", german).first, "80 Tage")
        XCTAssertEqual(card("days until Dec 25", japanese).first, "80日")
        XCTAssertEqual(card("weeks until Dec 25", german).first, "11 Wochen 3 Tage")
        XCTAssertEqual(card("workhours in 2023", german).first, "2.016 Stunden")
        XCTAssertEqual(card("workhours in 2023", french).first, "2 008 heures")
        XCTAssertEqual(card("age 1985-04-12", german).first, "41 Jahre")
        XCTAssertEqual(card("half of 3 hours", german).first, "1 Stunde 30 Minuten")
    }

    func testCurrencyUsesTheLocaleCurrencyFormat() throws {
        let rates = CurrencyRates(date: "2026-10-05", perEuro: ["USD": 1.25, "GBP": 0.8, "JPY": 160])
        XCTAssertEqual(CurrencyConverter.evaluate("100 usd in eur", rates: rates, now: now, locale: english)?.result, "€80.00")
        XCTAssertEqual(CurrencyConverter.evaluate("100 usd in eur", rates: rates, now: now, locale: german)?.result, "80,00 €")
        XCTAssertEqual(CurrencyConverter.evaluate("100 usd in eur", rates: rates, now: now, locale: french)?.result, "80,00 €")
        XCTAssertEqual(CurrencyConverter.evaluate("100 eur in usd", rates: rates, now: now, locale: german)?.result, "125,00 $")
    }

    func testCopyMatchesWhatTheCardShows() {
        for locale in [english, german, french, japanese] {
            for query in ["10 / 4", "145 mins to timespan", "days until Dec 25", "in 3 weeks", "5 km in mi", "workhours in 2023"] {
                let answer = first(query, locale)
                XCTAssertNotNil(answer, query)
                XCTAssertEqual(answer?.copyText, answer?.result, "\(query) in \(locale.identifier)")
            }
        }
        XCTAssertEqual(first("now", german)?.copyText, "Dienstag, 6. Oktober at 14:15")
        XCTAssertEqual(first("3pm est in cet", german)?.copyText, "21:00 CEST")
    }

    func testCodeValuesStayFixed() {
        for locale in [english, german, french, japanese] {
            XCTAssertEqual(first("#ff6363 in rgb", locale)?.result, "rgb(255 99 99)", locale.identifier)
            XCTAssertEqual(first("#ff6363 in hsl", locale)?.result, "hsl(0 100% 69.4%)", locale.identifier)
            XCTAssertEqual(first("rgb(255 99 99) in hex", locale)?.result, "#ff6363", locale.identifier)
            XCTAssertEqual(first("255 in hex", locale)?.result, "0xFF", locale.identifier)
            XCTAssertEqual(first("week number", locale)?.inputDetail, "ISO 8601", locale.identifier)
        }
    }

    func testSwapsRoundTripInEachLocale() throws {
        let rates = CurrencyRates(date: "2026-10-05", perEuro: ["USD": 1.25, "GBP": 0.8])
        for (locale, swapped) in [(english, "3.106856 mi in km"), (german, "3,106856 mi in km")] {
            XCTAssertEqual(first("5 km in mi", locale)?.swapQuery, swapped)
            XCTAssertEqual(first(swapped, locale)?.result, "5 km")
            let money = try XCTUnwrap(CurrencyConverter.evaluate("1.000 usd in gbp".replacingOccurrences(of: ".", with: locale == german ? "." : ","),
                                                                rates: rates, now: now, locale: locale))
            let back = try XCTUnwrap(money.swapQuery)
            XCTAssertEqual(back, "640 GBP in USD")
            XCTAssertNotNil(CurrencyConverter.evaluate(back, rates: rates, now: now, locale: locale))
            XCTAssertEqual(first("255 in hex", locale)?.swapQuery, "0xFF in decimal")
            XCTAssertEqual(first("0xFF in decimal", locale)?.result, "255")
            let time = try XCTUnwrap(first("3pm est in cet", locale)?.swapQuery)
            XCTAssertEqual(time, "9:00pm cet in est")
            XCTAssertEqual(TimeCalculator.evaluate(time, now: now, localZone: paris, locale: locale)?.date,
                           TimeCalculator.evaluate("3pm est", now: now, localZone: paris, locale: locale)?.date)
            XCTAssertEqual(first("1 cup flour in grams", locale)?.swapQuery, "120 g all-purpose flour in cups")
        }
        XCTAssertEqual(first("5 km in mi", german)?.result, "3,106856 mi")
    }

    func testUseAnswerReadsBackInTheLocale() {
        for locale in [english, german, french] {
            let answer = first("10 / 4 + 1000", locale)
            let copied = answer?.copyText ?? ""
            XCTAssertEqual(Calculator.evaluate(copied + " * 2", locale: locale), 2005, "\(copied) in \(locale.identifier)")
        }
    }
}
