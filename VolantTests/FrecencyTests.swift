import XCTest
@testable import Volant

final class FrecencyTests: XCTestCase {
    func testHalfLifeDecay() {
        let now = Date()
        let weekAgo = now.addingTimeInterval(-Frecency.halfLife)
        XCTAssertEqual(Frecency.decayed(score: 4, last: weekAgo, now: now), 2, accuracy: 0.001)
        XCTAssertEqual(Frecency.decayed(score: 4, last: now, now: now), 4, accuracy: 0.001)
    }

    func testDailyUseBeatsOldBinge() {
        let now = Date()
        var daily = 0.0; var last = now.addingTimeInterval(-30 * 86400)
        for d in stride(from: 29, through: 0, by: -1) {
            let t = now.addingTimeInterval(-Double(d) * 86400)
            daily = Frecency.bumped(score: daily, last: last, now: t); last = t
        }
        let binge = Frecency.decayed(score: 50, last: now.addingTimeInterval(-365 * 86400), now: now)
        XCTAssertGreaterThan(Frecency.decayed(score: daily, last: last, now: now), binge)
    }

    func testStoreRecordsAndPinsQueryChoice() {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("volant-usage-\(UUID().uuidString).sqlite")
        let store = UsageStore(url: url)
        store.record(key: "app:/Applications/Safari.app", query: "sa")
        store.record(key: "app:/Applications/Safari.app", query: "sa")
        store.record(key: "app:/Applications/Slack.app", query: "sl")
        XCTAssertGreaterThan(store.score("app:/Applications/Safari.app"), store.score("app:/Applications/Slack.app"))
        XCTAssertEqual(store.choice(forQuery: "SA "), "app:/Applications/Safari.app")
        XCTAssertEqual(store.top(prefix: "app:", limit: 5).first, "app:/Applications/Safari.app")
        try? FileManager.default.removeItem(at: url)
    }
}
