import XCTest
@testable import VolantCore

final class TimeCalculatorTests: XCTestCase {
    private let now = ISO8601DateFormatter().date(from: "2026-01-15T12:00:00Z")!
    private let paris = TimeZone(identifier: "Europe/Paris")!

    private func answer(_ query: String) -> TimeCalculator.Result? {
        TimeCalculator.evaluate(query, now: now, localZone: paris)
    }

    func testOwnerExampleAndImplicitLocalDestination() {
        XCTAssertTrue(answer("1pm EST in CET")?.text.hasPrefix("19:00") == true)
        XCTAssertEqual(answer("1pm in EST"), answer("1pm EST"))
        XCTAssertEqual(answer("1pm EST")?.date, ISO8601DateFormatter().date(from: "2026-01-15T18:00:00Z"))
    }

    func testCitiesAndDaylightSaving() {
        XCTAssertTrue(answer("5pm ldn in sf")?.text.hasPrefix("09:00") == true)
        XCTAssertTrue(answer("2026-03-15 3pm Los Angeles in Berlin")?.text.hasPrefix("23:00") == true)
        XCTAssertTrue(answer("2026-07-15 1pm New York in Paris")?.text.hasPrefix("19:00") == true)
        XCTAssertTrue(answer("2026-07-15 1pm EST in CET")?.text.hasPrefix("19:00") == true)
        XCTAssertTrue(answer("2026-07-15 1pm EST in Paris")?.text.hasPrefix("20:00") == true)
    }

    func testClockQueriesAndIANAIdentifiers() {
        XCTAssertTrue(answer("time in Tokyo")?.text.hasPrefix("21:00") == true)
        XCTAssertEqual(answer("now in Dubai"), answer("time in Dubai"))
        XCTAssertEqual(answer("17:30 Europe/London to America/Los_Angeles"), answer("5:30pm london in sf"))
        XCTAssertEqual(answer("  1 PM   EST in my time  "), answer("1pm EST"))
    }

    func testRolloverAndHalfHourOffsets() {
        XCTAssertTrue(answer("2026-12-31 3pm PST in CET")?.text.contains("2027-01-01") == true)
        XCTAssertTrue(answer("2026-01-01 1am Tokyo in sf")?.text.contains("2025-12-31") == true)
        XCTAssertTrue(answer("time in Kolkata")?.text.contains("17:30") == true)
        XCTAssertTrue(answer("time in Kolkata")?.text.contains("UTC+05:30") == true)
    }

    func testRejectsMalformedAmbiguousAndDSTTimes() {
        for query in ["Safari", "1pm", "1pm EST in", "1pm CST in CET", "1pm IST", "1pm France",
                      "25:00 EST", "0pm EST", "13pm EST", "1:60pm EST", "1 EST", "1pm EST garbage",
                      "2026-02-30 1pm EST", "2026-03-08 2:30am New York in Paris",
                      "2026-11-01 1:30am New York in Paris", "1pm EST in CET in Tokyo"] {
            XCTAssertNil(answer(query), query)
        }
        XCTAssertNil(answer(String(repeating: "1", count: 257)))
    }
}
