import XCTest
@testable import VolantCore

final class CurrencyConverterTests: XCTestCase {
    private let feed = """
    <?xml version="1.0" encoding="UTF-8"?>
    <gesmes:Envelope xmlns:gesmes="http://www.gesmes.org/xml/2002-08-01" xmlns="http://www.ecb.int/vocabulary/2002-08-01/eurofxref">
    <gesmes:subject>Reference rates</gesmes:subject>
    <Cube><Cube time='2026-10-05'>
    <Cube currency='USD' rate='1.25'/><Cube currency='JPY' rate='160'/><Cube currency='GBP' rate='0.8'/>
    <Cube currency='CHF' rate='0.95'/><Cube currency='INR' rate='100'/><Cube currency='SEK' rate='11.5'/>
    </Cube></Cube></gesmes:Envelope>
    """
    private let english = Locale(identifier: "en_US")
    private let now = ISO8601DateFormatter().date(from: "2026-10-06T10:00:00Z")!

    private func rates() throws -> CurrencyRates { try XCTUnwrap(CurrencyRates.parse(Data(feed.utf8))) }

    private func card(_ query: String) throws -> [String?] {
        guard let answer = CurrencyConverter.evaluate(query, rates: try rates(), now: now, locale: english) else { return [] }
        return [answer.result, answer.inputDetail, answer.resultDetail, answer.copyText]
    }

    func testParsesTheECBFeedAndRejectsAnythingElse() throws {
        let parsed = try rates()
        XCTAssertEqual(parsed.date, "2026-10-05")
        XCTAssertEqual(parsed.rate("USD"), 1.25)
        XCTAssertEqual(parsed.rate("EUR"), 1)
        XCTAssertNil(parsed.rate("XYZ"))
        XCTAssertNil(CurrencyRates.parse(Data("<html>Service unavailable</html>".utf8)))
        XCTAssertNil(CurrencyRates.parse(Data(feed.replacingOccurrences(of: "time='2026-10-05'", with: "").utf8)))
        XCTAssertNil(CurrencyRates.parse(Data(String(feed.prefix(400)).utf8)))
        XCTAssertNil(CurrencyRates.parse(Data(repeating: 32, count: CurrencyRates.maximumBytes + 1)))
        let encoded = try JSONEncoder().encode(parsed)
        XCTAssertEqual(try JSONDecoder().decode(CurrencyRates.self, from: encoded), parsed)
    }

    func testConvertsThroughTheEuro() throws {
        XCTAssertEqual(try card("100 usd in eur"), ["€80.00", "1 USD = 0.8 EUR", "ECB rates · Oct 5", "€80.00"])
        XCTAssertEqual(try card("100 USD to GBP").first, "£64.00")
        XCTAssertEqual(try card("10 gbp as jpy").first, "¥2,000")
        XCTAssertEqual(try card("50 eur in chf")[1], "1 EUR = 0.95 CHF")
    }

    func testSymbolsNamesCodesAndMagnitudes() throws {
        XCTAssertEqual(try card("$100 in gbp").first, "£64.00")
        XCTAssertEqual(try card("100$ in eur").first, "€80.00")
        XCTAssertEqual(try card("€50 to yen").first, "¥8,000")
        XCTAssertEqual(try card("20 pounds in euros").first, "€25.00")
        XCTAssertEqual(try card("USD1K in CHF").first, "CHF 760.00")
        XCTAssertEqual(try card("usd 1,000 in eur").first, "€800.00")
        XCTAssertEqual(try card("1.5M INR in USD").first, "$18,750.00")
    }

    func testOldRatesAreLabelled() throws {
        let later = ISO8601DateFormatter().date(from: "2026-10-20T10:00:00Z")!
        let answer = CurrencyConverter.evaluate("100 usd in eur", rates: try rates(), now: later, locale: english)
        XCTAssertEqual(answer?.resultDetail, "Old ECB rates · Oct 5")
    }

    func testNoRatesNoAnswerAndOtherUnitsStayAlone() throws {
        XCTAssertNil(CurrencyConverter.evaluate("100 usd in eur", rates: nil, now: now, locale: english))
        for query in ["5 pounds in kg", "100 usd in usd", "100 xyz in eur", "100 usd in", "usd in eur", "100 dollars", "Safari",
                      "100 aud in eur", "-5 usd in eur", "5 km in mi"] {
            XCTAssertNil(CurrencyConverter.evaluate(query, rates: try rates(), now: now, locale: english), query)
        }
        XCTAssertEqual(UnitConverter.convert("5 pounds in kg", locale: english)?.toSymbol, "kg")
    }

    func testRecognizesConversionsBeforeRatesExist() {
        XCTAssertTrue(CurrencyConverter.looksLikeConversion("100 usd in eur", locale: english))
        XCTAssertTrue(CurrencyConverter.looksLikeConversion("$5 to aud", locale: english))
        XCTAssertTrue(CurrencyConverter.looksLikeConversion("20 pounds in euros", locale: english))
        for query in ["5 km in mi", "100 xyz in eur", "2 + 2", "time in tokyo", "5 pounds in kg"] {
            XCTAssertFalse(CurrencyConverter.looksLikeConversion(query, locale: english), query)
        }
    }
}
