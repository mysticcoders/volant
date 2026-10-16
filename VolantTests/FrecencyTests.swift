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
