import XCTest
import VolantCore
@testable import Volant

final class FrecencyTests: XCTestCase {
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

/// Settings › Your Volant reads per-day counts beside the ranking, and clearing them keeps the ranking.
final class UsageActivityTests: XCTestCase {
    func testRecordCountsTodayAndSnapshotReadsIt() {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("volant-usage-\(UUID().uuidString).sqlite")
        defer { try? FileManager.default.removeItem(at: url) }
        let store = UsageStore(url: url)
        store.record(key: "app:/Applications/Fictional.app", query: "fi")
        store.record(key: "core:notes", query: "")
        store.record(key: "core:notes", query: "no")
        store.drain()
        let snapshot = UsageStore.snapshot(url: url)
        XCTAssertEqual(snapshot.daily, [UsageStats.dayKey(Date()): 3])
        XCTAssertEqual(Set(snapshot.records.map(\.key)), ["app:/Applications/Fictional.app", "core:notes"])
        XCTAssertTrue(UsageStore.clearActivity(url: url))
        let cleared = UsageStore.snapshot(url: url)
        XCTAssertTrue(cleared.daily.isEmpty)
        XCTAssertEqual(cleared.records.count, 2)
        XCTAssertGreaterThan(store.score("core:notes"), 0)
    }

    func testMissingStoreReadsAsEmpty() {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("volant-missing-\(UUID().uuidString).sqlite")
        let snapshot = UsageStore.snapshot(url: url)
        XCTAssertTrue(snapshot.daily.isEmpty)
        XCTAssertTrue(snapshot.records.isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
    }
}
