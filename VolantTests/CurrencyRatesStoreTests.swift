import XCTest
import VolantCore
@testable import Volant

final class CurrencyRatesStoreTests: XCTestCase {
    private let feed = Data("""
    <Envelope><Cube><Cube time='2026-10-05'><Cube currency='USD' rate='1.25'/><Cube currency='JPY' rate='160'/>
    <Cube currency='GBP' rate='0.8'/><Cube currency='CHF' rate='0.95'/><Cube currency='SEK' rate='11.5'/></Cube></Cube></Envelope>
    """.utf8)
    private var cacheURL: URL!
    private var clock = Date(timeIntervalSince1970: 1_790_000_000)
    private var requests = 0
    private var reply: Data?

    override func setUp() {
        cacheURL = FileManager.default.temporaryDirectory.appendingPathComponent("volant-rates-\(UUID().uuidString).json")
        CurrencyRates.current = nil
        requests = 0
        reply = feed
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: cacheURL)
        CurrencyRates.current = nil
    }

    private func store() -> CurrencyRatesStore {
        CurrencyRatesStore(cacheURL: cacheURL, now: { self.clock }, fetch: { completion in
            self.requests += 1
            completion(self.reply)
        })
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
