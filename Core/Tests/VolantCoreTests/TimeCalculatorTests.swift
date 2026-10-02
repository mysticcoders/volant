import XCTest
@testable import VolantCore

final class TimeCalculatorTests: XCTestCase {
    private let now = ISO8601DateFormatter().date(from: "2026-01-15T12:00:00Z")!
    private let paris = TimeZone(identifier: "Europe/Paris")!

    private func answer(_ query: String) -> TimeCalculator.Result? {
        TimeCalculator.evaluate(query, now: now, localZone: paris, locale: Locale(identifier: "en_US"))
    }

    func testOwnerExampleAndImplicitLocalDestination() {
        XCTAssertTrue(answer("1pm EST in CET")?.text.hasPrefix("7:00 PM") == true)
        XCTAssertEqual(answer("1pm in EST"), answer("1pm EST"))
        XCTAssertEqual(answer("1pm EST")?.date, ISO8601DateFormatter().date(from: "2026-01-15T18:00:00Z"))
    }

    func testCitiesAndDaylightSaving() {
        XCTAssertTrue(answer("5pm ldn in sf")?.text.hasPrefix("9:00 AM") == true)
        XCTAssertTrue(answer("2026-03-15 3pm Los Angeles in Berlin")?.text.hasPrefix("11:00 PM") == true)
        XCTAssertTrue(answer("2026-07-15 1pm New York in Paris")?.text.hasPrefix("7:00 PM") == true)
        XCTAssertTrue(answer("2026-07-15 1pm EST in CET")?.text.hasPrefix("7:00 PM") == true)
        XCTAssertTrue(answer("2026-07-15 1pm EST in Paris")?.text.hasPrefix("8:00 PM") == true)
    }

    func testClockQueriesAndIANAIdentifiers() {
        XCTAssertTrue(answer("time in Tokyo")?.text.hasPrefix("9:00 PM") == true)
        XCTAssertEqual(answer("now in Dubai"), answer("time in Dubai"))
        XCTAssertEqual(answer("17:30 Europe/London to America/Los_Angeles"), answer("5:30pm london in sf"))
        XCTAssertEqual(answer("  1 PM   EST in my time  "), answer("1pm EST"))
    }

    func testRolloverAndHalfHourOffsets() {
        XCTAssertTrue(answer("2026-12-31 3pm PST in CET")?.text.contains("Jan 1, 2027") == true)
        XCTAssertTrue(answer("2026-01-01 1am Tokyo in sf")?.text.contains("Dec 31, 2025") == true)
        XCTAssertTrue(answer("time in Kolkata")?.text.contains("5:30 PM") == true)
        XCTAssertEqual(answer("time in Kolkata")?.text, "5:30 PM in Kolkata")
    }

    func testReadableAnswersAndRelativeDays() {
        XCTAssertEqual(answer("1pm EST in CET")?.text, "7:00 PM CET")
        XCTAssertEqual(answer("1pm EST")?.text, "7:00 PM · your time")
        XCTAssertEqual(answer("3pm PST in CET")?.text, "Midnight CET · tomorrow")
        XCTAssertEqual(answer("1am Tokyo in sf")?.text, "8:00 AM in Los Angeles · yesterday")
        XCTAssertEqual(answer("11am UTC in CET")?.text, "Noon CET")
        XCTAssertEqual(answer("2026-07-15 1pm EST in Paris")?.text, "8:00 PM in Paris · Jul 15, 2026")
        XCTAssertEqual(answer("time in Tokyo")?.text, "9:00 PM in Tokyo")
    }

    func testRelativeDaysFollowTheUsersLocalDay() {
        let late = ISO8601DateFormatter().date(from: "2026-01-15T23:30:00Z")!
        let early = ISO8601DateFormatter().date(from: "2026-01-15T16:00:00Z")!
        XCTAssertEqual(TimeCalculator.evaluate("1pm EST", now: late, localZone: paris,
                                              locale: Locale(identifier: "en_US"))?.text,
                       "7:00 PM · your time · yesterday")
        XCTAssertEqual(TimeCalculator.evaluate("1am Tokyo in sf", now: early, localZone: paris,
                                              locale: Locale(identifier: "en_US"))?.text,
                       "8:00 AM in Los Angeles")
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
