import XCTest
import VolantCore
@testable import Volant

final class CurrencyRatesStoreTests: XCTestCase {
    private let feed = Data("""
    <Envelope><Cube><Cube time='2026-10-05'><Cube currency='USD' rate='1.25'/><Cube currency='JPY' rate='160'/>
    <Cube currency='GBP' rate='0.8'/><Cube currency='CHF' rate='0.95'/><Cube currency='SEK' rate='11.5'/></Cube></Cube></Envelope>
    """.utf8)
    private var cacheURL: URL!
    private var cryptoCacheURL: URL!
    private var worldCacheURL: URL!
    private var worldRequests = 0
    private var worldReply: Data?
    private let worldBody: Data = {
        let letters = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZ")
        let padding = (0..<50).map { "\"Q\(letters[$0 / 26])\(letters[$0 % 26])\": \($0 + 1)" }
        let rates = (["\"USD\": 1.2", "\"AED\": 4.4", "\"TWD\": 36"] + padding).joined(separator: ", ")
        return Data("{\"result\": \"success\", \"base_code\": \"EUR\", \"time_last_update_unix\": 1790000000, \"rates\": {\(rates)}}".utf8)
    }()
    private var key: String?
    private var cryptoRequests: [String?] = []
    private var cryptoReply: Data?
    private var cryptoMessage: String?
    private let cryptoBody = Data(#"{"bitcoin":{"eur":50000},"ethereum":{"eur":2000},"solana":{"eur":100},"ripple":{"eur":0.5},"binancecoin":{"eur":400},"cardano":{"eur":0.25}}"#.utf8)
    private var clock = Date(timeIntervalSince1970: 1_790_000_000)
    private var requests = 0
    private var reply: Data?

    override func setUp() {
        cacheURL = FileManager.default.temporaryDirectory.appendingPathComponent("volant-rates-\(UUID().uuidString).json")
        cryptoCacheURL = FileManager.default.temporaryDirectory.appendingPathComponent("volant-crypto-\(UUID().uuidString).json")
        worldCacheURL = FileManager.default.temporaryDirectory.appendingPathComponent("volant-world-\(UUID().uuidString).json")
        worldRequests = 0
        worldReply = worldBody
        WorldRates.current = nil
        key = nil
        cryptoRequests = []
        cryptoReply = cryptoBody
        cryptoMessage = nil
        CurrencyRates.current = nil
        CryptoPrices.current = nil
        requests = 0
        reply = feed
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: cacheURL)
        try? FileManager.default.removeItem(at: cryptoCacheURL)
        try? FileManager.default.removeItem(at: worldCacheURL)
        CurrencyRates.current = nil
        WorldRates.current = nil
        CryptoPrices.current = nil
    }

    private func store() -> CurrencyRatesStore {
        CurrencyRatesStore(cacheURL: cacheURL, cryptoCacheURL: cryptoCacheURL, worldCacheURL: worldCacheURL, now: { self.clock }, fetch: { completion in
            self.requests += 1
            completion(self.reply)
        }, fetchWorld: { completion in
            self.worldRequests += 1
            completion(self.worldReply, self.worldReply == nil ? "Couldn’t get exchange rates." : nil)
        }, fetchCrypto: { key, completion in
            self.cryptoRequests.append(key)
            completion(self.cryptoReply, self.cryptoReply == nil ? self.cryptoMessage : nil)
        }, cryptoKey: { self.key })
    }

    private func settle() { RunLoop.main.run(until: Date().addingTimeInterval(0.05)) }

    func testOnlyCurrencyConversionsFetchAndRatesInstallWithACache() {
        let rates = store()
        var updates = 0
        rates.onUpdate = { updates += 1 }
        for query in ["2 + 2", "5 km in mi", "time in tokyo", "Safari"] { rates.noteQuery(query) }
        XCTAssertEqual(requests, 0)
        rates.noteQuery("100 usd in eur")
        settle()
        XCTAssertEqual(requests, 1)
        XCTAssertEqual(updates, 1)
        XCTAssertEqual(CurrencyRates.current?.date, "2026-10-05")
        XCTAssertTrue(FileManager.default.fileExists(atPath: cacheURL.path))
    }

    func testRefreshesAtMostEveryTwelveHoursAndRetriesFailuresHourly() {
        let rates = store()
        rates.noteQuery("100 usd in eur"); settle()
        rates.noteQuery("50 gbp in eur"); settle()
        XCTAssertEqual(requests, 1)
        clock += CurrencyRatesStore.refreshInterval + 1
        reply = nil
        rates.noteQuery("100 usd in eur"); settle()
        XCTAssertEqual(requests, 2)
        XCTAssertEqual(CurrencyRates.current?.date, "2026-10-05", "A failed refresh keeps the rates already installed")
        clock += 60
        rates.noteQuery("100 usd in eur"); settle()
        XCTAssertEqual(requests, 2)
        clock += CurrencyRatesStore.retryInterval
        reply = feed
        rates.noteQuery("100 usd in eur"); settle()
        XCTAssertEqual(requests, 3)
    }

    func testCacheSurvivesRestartWithoutTouchingTheNetwork() {
        let first = store()
        first.noteQuery("100 usd in eur"); settle()
        CurrencyRates.current = nil
        let restarted = store()
        restarted.loadCache()
        XCTAssertEqual(CurrencyRates.current?.rate("USD"), 1.25)
        restarted.noteQuery("100 usd in eur"); settle()
        XCTAssertEqual(requests, 1, "Fresh cached rates need no fetch")
    }

    func testCryptoFetchesKeylessForCoinQueriesOnly() {
        let rates = store()
        rates.noteQuery("100 usd in eur"); settle()
        XCTAssertTrue(cryptoRequests.isEmpty, "Fiat conversions never fetch crypto")
        rates.noteQuery("0.5 btc in usd"); settle()
        XCTAssertEqual(cryptoRequests, [nil], "No key still fetches, keyless")
        XCTAssertEqual(CryptoPrices.current?.euros["BTC"], 50000)
        XCTAssertTrue(FileManager.default.fileExists(atPath: cryptoCacheURL.path))
    }

    func testCryptoSendsASavedKey() {
        key = "CG-fixturekey123"
        let rates = store()
        rates.noteQuery("0.5 btc in usd"); settle()
        XCTAssertEqual(cryptoRequests, ["CG-fixturekey123"])
    }

    func testCryptoRefreshesAtMostEveryTenMinutes() {
        let rates = store()
        rates.noteQuery("1 eth in eur"); settle()
        clock += 300
        rates.noteQuery("1 eth in eur"); settle()
        XCTAssertEqual(cryptoRequests.count, 1)
        clock += CurrencyRatesStore.cryptoRefreshInterval
        cryptoReply = nil
        rates.noteQuery("1 eth in eur"); settle()
        XCTAssertEqual(cryptoRequests.count, 2)
        XCTAssertEqual(CryptoPrices.current?.euros["ETH"], 2000, "A failed refresh keeps the prices already installed")
        clock += 60
        rates.noteQuery("1 eth in eur"); settle()
        XCTAssertEqual(cryptoRequests.count, 2, "Waits after a failure")
        clock += CurrencyRatesStore.cryptoRetryInterval
        rates.noteQuery("1 eth in eur"); settle()
        XCTAssertEqual(cryptoRequests.count, 3)
    }

    func testCryptoWaitsLongerWhenCoinGeckoIsBusy() {
        cryptoReply = nil
        cryptoMessage = CryptoPrices.busyMessage
        let rates = store()
        rates.noteQuery("1 btc in eur"); settle()
        clock += CurrencyRatesStore.cryptoRetryInterval + 1
        rates.noteQuery("1 btc in eur"); settle()
        XCTAssertEqual(cryptoRequests.count, 1, "A 429 waits longer than an ordinary failure")
        rates.keyChanged()
        rates.noteQuery("1 btc in eur"); settle()
        XCTAssertEqual(cryptoRequests.count, 1, "Unrelated settings changes keep the wait")
        clock += CurrencyRatesStore.cryptoBusyInterval
        cryptoReply = cryptoBody
        rates.noteQuery("1 btc in eur"); settle()
        XCTAssertEqual(cryptoRequests.count, 2)
    }

    func testChangingTheKeyKeepsPricesAndRetriesWithTheNewSetting() {
        key = "CG-fixturekey123"
        let rates = store()
        rates.noteQuery("1 btc in eur"); settle()
        XCTAssertNotNil(CryptoPrices.current)
        key = nil
        rates.keyChanged()
        XCTAssertEqual(CryptoPrices.current?.euros["BTC"], 50000, "Prices are the same public data without a key")
        XCTAssertTrue(FileManager.default.fileExists(atPath: cryptoCacheURL.path))
        CryptoPrices.current = nil
        let restarted = store()
        restarted.loadCache()
        XCTAssertEqual(CryptoPrices.current?.euros["BTC"], 50000, "Cached prices load without a key")
        cryptoReply = nil
        clock += CurrencyRatesStore.cryptoRefreshInterval
        rates.noteQuery("1 btc in eur"); settle()
        XCTAssertEqual(cryptoRequests, ["CG-fixturekey123", nil])
        key = "CG-otherkey45678"
        rates.keyChanged()
        rates.noteQuery("1 btc in eur"); settle()
        XCTAssertEqual(cryptoRequests.last, "CG-otherkey45678", "A new key skips the failure wait")
    }

    func testWorldRatesFetchOnlyForCurrenciesTheECBLacks() {
        let rates = store()
        var updates = 0
        rates.onUpdate = { updates += 1 }
        for query in ["100 usd in eur", "0.5 btc in usd", "2 + 2", "Safari"] { rates.noteQuery(query) }
        settle()
        XCTAssertEqual(worldRequests, 0, "ECB currencies and coins never fetch the second source")
        rates.noteQuery("100 aed in usd"); settle()
        XCTAssertEqual(worldRequests, 1)
        XCTAssertEqual(WorldRates.current?.rate("AED"), 4.4)
        XCTAssertTrue(FileManager.default.fileExists(atPath: worldCacheURL.path))
        XCTAssertGreaterThanOrEqual(updates, 1)
        rates.noteQuery("500 twd in usd"); settle()
        XCTAssertEqual(worldRequests, 1, "Fresh rates need no second fetch")
        WorldRates.current = nil
        let restarted = store()
        restarted.loadCache()
        XCTAssertEqual(WorldRates.current?.rate("TWD"), 36, "Cached rates load without touching the network")
        restarted.noteQuery("100 aed in usd"); settle()
        XCTAssertEqual(worldRequests, 1)
    }

    func testWorldRatesRefreshTwiceADayAndRetryFailuresHourly() {
        let rates = store()
        rates.noteQuery("100 aed in usd"); settle()
        clock += CurrencyRatesStore.refreshInterval + 1
        worldReply = nil
        rates.noteQuery("100 aed in usd"); settle()
        XCTAssertEqual(worldRequests, 2)
        XCTAssertEqual(WorldRates.current?.rate("AED"), 4.4, "A failed refresh keeps the rates already installed")
        clock += 60
        rates.noteQuery("100 aed in usd"); settle()
        XCTAssertEqual(worldRequests, 2, "Waits after a failure")
        clock += CurrencyRatesStore.retryInterval
        worldReply = worldBody
        rates.noteQuery("100 aed in usd"); settle()
        XCTAssertEqual(worldRequests, 3)
    }

    func testRejectsAResponseThatIsNotTheFeed() {
        reply = Data("<html>Maintenance</html>".utf8)
        let rates = store()
        var updates = 0
        rates.onUpdate = { updates += 1 }
        rates.noteQuery("100 usd in eur"); settle()
        XCTAssertNil(CurrencyRates.current)
        XCTAssertEqual(updates, 0)
        XCTAssertFalse(FileManager.default.fileExists(atPath: cacheURL.path))
    }
}
