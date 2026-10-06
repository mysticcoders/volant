import XCTest
@testable import VolantCore

final class CryptoPricesTests: XCTestCase {
    private let english = Locale(identifier: "en_US")
    private let paris = TimeZone(identifier: "Europe/Paris")!
    private let fetched = ISO8601DateFormatter().date(from: "2026-10-06T12:00:00Z")!
    private let rates = CurrencyRates(date: "2026-10-05", perEuro: ["USD": 1.25, "GBP": 0.8, "JPY": 160, "CHF": 0.95, "SEK": 11.5])
    private let body = Data(#"{"bitcoin":{"eur":50000},"ethereum":{"eur":2000},"solana":{"eur":100},"ripple":{"eur":0.5},"binancecoin":{"eur":400},"cardano":{"eur":0.25},"dogecoin":{"eur":0.1}}"#.utf8)

    private func prices() throws -> CryptoPrices { try XCTUnwrap(CryptoPrices.parse(body, at: fetched)) }

    private func card(_ query: String, rates: CurrencyRates? = nil, minutesLater: Double = 5) throws -> [String?] {
        let answer = CurrencyConverter.evaluate(query, rates: rates ?? self.rates, crypto: try prices(),
                                                now: fetched.addingTimeInterval(minutesLater * 60), zone: paris, locale: english)
        return answer.map { [$0.result, $0.inputDetail, $0.resultDetail, $0.swapQuery] } ?? []
    }

    func testParsesCoinGeckoAndRejectsPartialOrErrorBodies() throws {
        XCTAssertEqual(try prices().euros["BTC"], 50000)
        XCTAssertEqual(try prices().euros.count, 7)
        XCTAssertNil(CryptoPrices.parse(Data(#"{"status":{"error_code":429}}"#.utf8), at: fetched))
        XCTAssertNil(CryptoPrices.parse(Data(#"{"bitcoin":{"eur":50000}}"#.utf8), at: fetched), "Fewer than half the coins")
        XCTAssertNil(CryptoPrices.parse(Data(#"{"bitcoin":{"eur":-1},"ethereum":{"eur":0}}"#.utf8), at: fetched))
        XCTAssertNil(CryptoPrices.parse(Data(repeating: 32, count: CryptoPrices.maximumBytes + 1), at: fetched))
        XCTAssertTrue(CryptoPrices.request.absoluteString.hasPrefix("https://api.coingecko.com/api/v3/simple/price?ids=bitcoin,ethereum"))
    }

    func testKeysAreShortTokens() {
        XCTAssertTrue(CryptoPrices.validKey("CG-abcDEF123456"))
        for key in ["", "short", "has space here", "semi;colon-key-123", String(repeating: "a", count: 129)] {
            XCTAssertFalse(CryptoPrices.validKey(key), key)
        }
    }

    func testCoinsConvertThroughTheirEuroPrice() throws {
        XCTAssertEqual(try card("0.5 btc in usd"), ["$31,250.00", "1 BTC = 62,500 USD", "CoinGecko · 2:00 PM", "31250 USD in BTC"])
        XCTAssertEqual(try card("100 eur in eth"), ["0.05 ETH", "1 EUR = 0.0005 ETH", "CoinGecko · 2:00 PM", "0.05 ETH in EUR"])
        XCTAssertEqual(try card("1 bitcoin in ether").first, "25 ETH")
        XCTAssertEqual(try card("1000 doge in gbp").first, "£80.00")
        XCTAssertEqual(try card("$100 in btc").first, "0.0016 BTC")
        XCTAssertEqual(try card("2 sol in usd").first, "$250.00")
    }

    func testTagsShowAgeAndFiatStaysWithECB() throws {
        XCTAssertEqual(try card("1 btc in eur", minutesLater: 90)[2], "Old CoinGecko prices · 2:00 PM")
        XCTAssertEqual(try card("100 usd in eur")[2], "ECB rates · Oct 5")
        let alone = CurrencyConverter.evaluate("1 btc in eur", rates: nil, crypto: try prices(), now: fetched, zone: paris, locale: english)
        XCTAssertEqual(alone?.result, "€50,000.00")
        XCTAssertNil(CurrencyConverter.evaluate("1 btc in usd", rates: nil, crypto: try prices(), now: fetched, zone: paris, locale: english))
        XCTAssertNil(CurrencyConverter.evaluate("1 usdt in eur", rates: rates, crypto: try prices(), now: fetched, zone: paris, locale: english),
                     "Coins missing from the response give no answer")
    }

    func testRecognizesCoinsBeforePricesExist() {
        XCTAssertTrue(CurrencyConverter.involvesCrypto("0.5 btc in usd", locale: english))
        XCTAssertTrue(CurrencyConverter.involvesCrypto("100 eur in ether", locale: english))
        XCTAssertFalse(CurrencyConverter.involvesCrypto("100 usd in eur", locale: english))
        XCTAssertFalse(CurrencyConverter.involvesCrypto("5 km in mi", locale: english))
        XCTAssertNil(CurrencyConverter.evaluate("0.5 btc in usd", rates: rates, crypto: nil, now: fetched, locale: english))
    }
}
