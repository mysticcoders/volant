import XCTest

@testable import VolantCore

/// The in-memory activity log behind Settings › Extensions › Activity: its bound and dropped count,
/// the history's filters, and the export, which carries exactly each event's fields. All fictional.
final class ExtensionActivityLogTests: XCTestCase {
    private func event(_ id: String, _ invocation: Int, _ operation: ExtensionActivity.Operation = .module,
                       _ outcome: ExtensionActivity.Outcome = .completed, detail: String? = nil, duration: TimeInterval? = nil) -> ExtensionActivity {
        ExtensionActivity(extensionID: id, version: "1", codeHash: "abc", invocation: invocation,
                          time: Date(timeIntervalSince1970: 1_800_000_000 + Double(invocation)), operation: operation,
                          outcome: outcome, detail: detail, duration: duration)
    }

    func testTheLogKeepsTheNewestAndCountsWhatItDropped() {
        var log = ExtensionActivityLog(capacity: 3)
        for invocation in 1...5 { log.record(event("fixture.reader", invocation)) }
        XCTAssertEqual(log.events.map(\.invocation), [3, 4, 5])
        XCTAssertEqual(log.dropped, 2)
        log.clear()
        XCTAssertTrue(log.events.isEmpty)
        XCTAssertEqual(log.dropped, 0)
    }

    func testTheHistoryShowsNewestFirstAndFiltersByExtensionAndProblems() {
        var log = ExtensionActivityLog()
        log.record(event("fixture.reader", 1))
        log.record(event("fixture.weather", 2, .fetch, .denied, detail: "api.example.com"))
        log.record(event("fixture.reader", 3, .clipboardRead, .timedOut))
        log.record(event("fixture.reader", 4, .storageSave))
        XCTAssertEqual(log.visible(extensionID: nil, problemsOnly: false).map(\.invocation), [4, 3, 2, 1])
        XCTAssertEqual(log.visible(extensionID: "fixture.reader", problemsOnly: false).map(\.invocation), [4, 3, 1])
        XCTAssertEqual(log.visible(extensionID: nil, problemsOnly: true).map(\.invocation), [3, 2])
        XCTAssertEqual(log.visible(extensionID: "fixture.weather", problemsOnly: true).map(\.invocation), [2])
        XCTAssertEqual(log.extensionIDs, ["fixture.reader", "fixture.weather"])
    }

    func testTheExportCarriesEachEventsFieldsAndTheDroppedCount() throws {
        let events = [event("fixture.weather", 7, .fetch, .denied, detail: "api.example.com", duration: 0.1234),
                      event("fixture.weather", 7, .module, .completed, detail: "plan")]
        let data = try ExtensionActivityExport.json(events, dropped: 12, exportedAt: Date(timeIntervalSince1970: 1_800_000_100))
        let file = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(file["droppedEarlierEvents"] as? Int, 12)
        XCTAssertEqual(file["exportedAt"] as? String, "2027-01-15T08:01:40Z")
        let first = try XCTUnwrap((file["events"] as? [[String: Any]])?.first)
        XCTAssertEqual(Set(first.keys), ["extensionID", "version", "codeHash", "invocation", "time", "operation", "outcome",
                                         "detail", "durationMilliseconds"])
        XCTAssertEqual(first["operation"] as? String, "fetch")
        XCTAssertEqual(first["outcome"] as? String, "denied")
        XCTAssertEqual(first["detail"] as? String, "api.example.com")
        XCTAssertEqual(first["durationMilliseconds"] as? Int, 123)
        XCTAssertEqual((file["events"] as? [[String: Any]])?.count, 2)
    }
}
