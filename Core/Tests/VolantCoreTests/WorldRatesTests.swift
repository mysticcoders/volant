import XCTest
@testable import VolantCore

final class WorldRatesTests: XCTestCase {
    private let english = Locale(identifier: "en_US")
    private let utc = TimeZone(identifier: "UTC")!
    private let updated = ISO8601DateFormatter().date(from: "2026-10-06T00:02:32Z")!
    private let now = ISO8601DateFormatter().date(from: "2026-10-06T10:00:00Z")!
    private let ecbFeed = """
    <Envelope><Cube><Cube time='2026-10-05'><Cube currency='USD' rate='1.25'/><Cube currency='JPY' rate='160'/>
    <Cube currency='GBP' rate='0.8'/><Cube currency='CHF' rate='0.95'/><Cube currency='SEK' rate='11.5'/></Cube></Cube></Envelope>
    """

    override func tearDown() {
        CurrencyRates.current = nil
    }

    /// A fictional euro-based response: a few real codes with round numbers, padded with made-up
    /// codes to the size the parser expects.
    private func body(result: String = "success", base: String = "EUR", time: Bool = true, fillers: Int = 50,
                      extra: String = "") -> Data {
        let letters = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZ")
        let padding = (0..<fillers).map { "\"Q\(letters[$0 / 26])\(letters[$0 % 26])\": \($0 + 1)" }
        let rates = ["\"EUR\": 1", "\"USD\": 1.2", "\"AED\": 4.4", "\"TWD\": 36", "\"VND\": 30000", "\"NGN\": 1500"] + padding
        let stamp = time ? "\"time_last_update_unix\": \(Int(updated.timeIntervalSince1970))," : ""
        return Data("""
        {"result": "\(result)", "provider": "https://www.exchangerate-api.com", "base_code": "\(base)", \(stamp) \(extra)
         "rates": {\(rates.joined(separator: ", "))}}
        """.utf8)
    }

    private func world() throws -> WorldRates { try XCTUnwrap(WorldRates.parse(body())) }

    private func ecb() throws -> CurrencyRates { try XCTUnwrap(CurrencyRates.parse(Data(ecbFeed.utf8))) }

    private func card(_ query: String, rates: CurrencyRates? = nil, crypto: CryptoPrices? = nil, at time: Date? = nil) throws -> CalculationAnswer? {
        CurrencyConverter.evaluate(query, rates: rates, world: try world(), crypto: crypto, now: time ?? now, zone: utc, locale: english)
    }

    func testParsesTheEuroBasedResponseAndRejectsAnythingElse() throws {
        let parsed = try world()
        XCTAssertEqual(parsed.updated, updated)
        XCTAssertEqual(parsed.rate("AED"), 4.4)
        XCTAssertEqual(parsed.rate("EUR"), 1)
        XCTAssertNil(parsed.perEuro["EUR"])
        XCTAssertNil(parsed.rate("XYZ"))
        XCTAssertNil(WorldRates.parse(Data(#"{"result": "error", "error-type": "unsupported-code"}"#.utf8)))
        XCTAssertNil(WorldRates.parse(body(result: "error")))
        XCTAssertNil(WorldRates.parse(body(base: "USD")))
        XCTAssertNil(WorldRates.parse(body(time: false)))
        XCTAssertNil(WorldRates.parse(body(fillers: 40)))
        XCTAssertNil(WorldRates.parse(Data("<html>Too many requests</html>".utf8)))
        XCTAssertNil(WorldRates.parse(Data(repeating: 32, count: WorldRates.maximumBytes + 1)))
        let encoded = try JSONEncoder().encode(parsed)
        XCTAssertEqual(try JSONDecoder().decode(WorldRates.self, from: encoded), parsed)
    }

    func testSkipsInvalidRatesAndCodes() throws {
        let parsed = try XCTUnwrap(WorldRates.parse(body(extra: "")))
        XCTAssertEqual(parsed.perEuro.count, 55)
        let noisy = Data(String(decoding: body(), as: UTF8.self)
            .replacingOccurrences(of: "\"AED\": 4.4", with: "\"AED\": -4.4, \"aed\": 4, \"AEDX\": 4, \"A1D\": 4").utf8)
        let filtered = try XCTUnwrap(WorldRates.parse(noisy))
        XCTAssertNil(filtered.rate("AED"))
        XCTAssertEqual(filtered.perEuro.count, 54)
    }

    func testConvertsCurrenciesTheECBLacks() throws {
        let answer = try XCTUnwrap(try card("100 aed in usd", rates: try ecb()))
        XCTAssertEqual(answer.result, "$27.27")
        XCTAssertEqual(answer.inputDetail, "1 AED = 0.27273 USD")
        XCTAssertEqual(answer.resultDetail, "Rates By Exchange Rate API · Oct 6")
        XCTAssertEqual(answer.swapQuery, "27.27 USD in AED")
        XCTAssertEqual(try card("1000 twd to vnd")?.result, CurrencyConverter.money(1000.0 / 36 * 30000, "VND", locale: english))
        XCTAssertEqual(try card("€10 in aed")?.result, CurrencyConverter.money(44, "AED", locale: english))
    }

    func testOneConversionNeverMixesTwoProvidersRates() throws {
        let ecb = try ecb()
        XCTAssertEqual(try card("100 usd in eur", rates: ecb)?.result, "€80.00")
        XCTAssertEqual(try card("100 usd in eur", rates: ecb)?.resultDetail, "ECB rates · Oct 5")
        let mixed = try XCTUnwrap(try card("120 usd in aed", rates: ecb))
        XCTAssertEqual(mixed.result, CurrencyConverter.money(440, "AED", locale: english))
        XCTAssertEqual(mixed.inputDetail, "1 USD = 3.6667 AED")
        XCTAssertEqual(try card("100 usd in eur")?.resultDetail, "Rates By Exchange Rate API · Oct 6")
    }

    func testNeedsTheProvidersRatesToAnswer() throws {
        XCTAssertNil(CurrencyConverter.evaluate("100 aed in usd", rates: try ecb(), world: nil, crypto: nil, now: now, locale: english))
        XCTAssertNil(try card("100 xyz in usd"))
    }

    func testMarksRatesOldAfterThreeDays() throws {
        let later = now.addingTimeInterval(4 * 86_400)
        XCTAssertEqual(try card("100 aed in usd", at: later)?.resultDetail, "Old rates by Exchange Rate API · Oct 6")
    }

    func testReadsSymbolsAndNamesThatMeanOneCurrency() throws {
        XCTAssertEqual(try card("₦1500 in eur")?.result, "€1.00")
        XCTAssertEqual(try card("30000 dong in eur")?.result, "€1.00")
        XCTAssertEqual(try card("4.4 dirham in eur")?.result, nil)
    }

    func testCoinsCrossWithTheProvidersRates() throws {
        let prices = CryptoPrices(fetchedAt: now, euros: ["BTC": 50_000])
        let answer = try XCTUnwrap(try card("0.01 btc in aed", rates: try ecb(), crypto: prices))
        XCTAssertEqual(answer.result, CurrencyConverter.money(2200, "AED", locale: english))
        XCTAssertTrue(answer.resultDetail?.hasPrefix("CoinGecko") == true)
    }

    func testFetchesOnlyForCurrenciesTheECBLacks() throws {
        CurrencyRates.current = nil
        XCTAssertTrue(CurrencyConverter.needsWorldRates("100 aed in usd", locale: english))
        XCTAssertTrue(CurrencyConverter.needsWorldRates("₦5000 in gbp", locale: english))
        for query in ["100 usd in eur", "1 btc in usd", "1 btc in eur", "2 + 2", "5 km in mi"] {
            XCTAssertFalse(CurrencyConverter.needsWorldRates(query, locale: english), query)
        }
        CurrencyRates.current = try ecb()
        XCTAssertTrue(CurrencyConverter.needsWorldRates("100 inr in usd", locale: english))
        XCTAssertFalse(CurrencyConverter.needsWorldRates("100 chf in usd", locale: english))
    }
}
