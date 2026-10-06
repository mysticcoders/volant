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
        XCTAssertEqual(answer("2026-07-15 1pm EST in CET")?.text, "7:00 PM CEST · Jul 15, 2026")
        XCTAssertEqual(answer("2026-07-15 1pm EST in Paris"), answer("2026-07-15 1pm New York in Paris"))
        XCTAssertEqual(answer("2026-07-15 1pm EDT in CEST"), answer("2026-07-15 1pm EST in CET"))
    }

    func testRegionalAbbreviationsFollowTheRegionsSummerTime() {
        let october = ISO8601DateFormatter().date(from: "2026-10-02T09:00:00Z")!
        func summer(_ query: String) -> String? {
            TimeCalculator.evaluate(query, now: october, localZone: paris, locale: Locale(identifier: "en_US"))?.text
        }
        XCTAssertEqual(summer("4pm in CET"), "4:00 PM · your time")
        XCTAssertEqual(summer("4pm CET"), "4:00 PM · your time")
        XCTAssertEqual(summer("1pm EST in CET"), "7:00 PM CEST")
        XCTAssertEqual(summer("9am PST in EST"), "Noon EDT")
        XCTAssertEqual(summer("5pm BST in UTC"), "4:00 PM UTC")
        XCTAssertEqual(summer("4pm UTC in CET"), "6:00 PM CEST")
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
        XCTAssertEqual(answer("2026-07-15 1pm EST in Paris")?.text, "7:00 PM in Paris · Jul 15, 2026")
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

    private func friday(_ query: String) -> TimeCalculator.Result? {
        TimeCalculator.evaluate(query, now: ISO8601DateFormatter().date(from: "2026-10-02T09:00:00Z")!,
                                localZone: paris, locale: Locale(identifier: "en_US"))
    }

    func testDayWordsResolveALocalMomentWithoutAZone() throws {
        let evening = try XCTUnwrap(friday("7:30pm tomorrow"))
        XCTAssertEqual(evening.headline, "Tomorrow at 7:30 PM")
        XCTAssertEqual(evening.detail, "Saturday")
        XCTAssertEqual(evening.source, "Saturday, October 3")
        XCTAssertEqual(evening.text, "Saturday, October 3 at 7:30 PM")
        XCTAssertEqual(evening.date, ISO8601DateFormatter().date(from: "2026-10-03T17:30:00Z"))
        XCTAssertEqual(friday("tomorrow at 19:30"), evening)
        XCTAssertEqual(friday("Tomorrow   7:30 PM"), evening)
        XCTAssertEqual(friday("friday 3pm")?.headline, "Today at 3:00 PM")
        XCTAssertEqual(friday("tonight 9pm")?.detail, "Friday")
        XCTAssertEqual(friday("yesterday 10pm")?.headline, "Yesterday at 10:00 PM")
        let monday = try XCTUnwrap(friday("monday 9am"))
        XCTAssertEqual(monday.headline, "Monday at 9:00 AM")
        XCTAssertEqual(monday.detail, "In 3 days")
        XCTAssertEqual(monday.source, "Monday, October 5")
        XCTAssertEqual(friday("tomorrow 12pm")?.headline, "Tomorrow at noon")
    }

    func testNextAndThisWeekdayInTimeQueries() {
        XCTAssertEqual(friday("3pm next friday")?.headline, "Friday at 3:00 PM")
        XCTAssertEqual(friday("3pm next friday")?.detail, "In 7 days")
        XCTAssertEqual(friday("this friday 3pm")?.headline, "Today at 3:00 PM")
        XCTAssertEqual(friday("next monday 9am EST in CET")?.source, "Monday, October 5")
        XCTAssertNil(friday("next 3pm"))
    }

    func testDayWordsCombineWithZonesInAnyPosition() throws {
        let meeting = try XCTUnwrap(friday("tomorrow 9am EST in CET"))
        XCTAssertEqual(meeting.text, "3:00 PM CEST · tomorrow")
        XCTAssertEqual(meeting.source, "Saturday, October 3")
        XCTAssertEqual(friday("9am EST tomorrow in CET"), meeting)
        XCTAssertEqual(friday("tomorrow at 9am EST in CET"), meeting)
        XCTAssertEqual(friday("7:30pm tomorrow in Tokyo")?.text, "12:30 PM · your time · tomorrow")
    }

    func testIANACityNamesWorkWithoutTheirRegion() {
        XCTAssertEqual(friday("3pm lisbon in tokyo")?.text, "11:00 PM in Tokyo")
        XCTAssertEqual(friday("time in buenos aires")?.headline.hasSuffix("in Buenos Aires"), true)
        XCTAssertEqual(friday("3pm Europe/Lisbon in Tokyo"), friday("3pm lisbon in tokyo"))
    }

    func testDayWordsNeverTurnPlainTextIntoAnAnswer() {
        for query in ["tomorrow", "monday", "1pm", "7 tomorrow", "tomorrow 25:00", "7pm tomorrow yesterday",
                      "2026-10-05 9am tomorrow", "time in tokyo tomorrow", "tomorrow 9am CST"] {
            XCTAssertNil(friday(query), query)
        }
    }

    func testTimeDifferenceFromTheOwnersClock() throws {
        let tokyo = try XCTUnwrap(friday("time diff Tokyo"))
        XCTAssertEqual(tokyo.headline, "7 hours ahead")
        XCTAssertEqual(tokyo.text, "Tokyo is 7 hours ahead")
        XCTAssertEqual(tokyo.detail, "6:00 PM in Tokyo")
        XCTAssertEqual(tokyo.source, "Now")
        XCTAssertEqual(friday("diff New York")?.text, "New York is 6 hours behind")
        XCTAssertEqual(friday("time difference with Kolkata")?.headline, "3 hours 30 minutes ahead")
        XCTAssertEqual(friday("diff to berlin")?.headline, "Same time")
        XCTAssertEqual(friday("diff Berlin")?.text, "Berlin is on your time")
        XCTAssertEqual(friday("diff EST")?.text, "EDT is 6 hours behind")
        XCTAssertEqual(friday("diff EST")?.detail, "5:00 AM EDT")
        XCTAssertEqual(friday("diff Adelaide")?.headline, "7 hours 30 minutes ahead")
        XCTAssertNil(friday("diff"))
        XCTAssertNil(friday("diff Atlantis"))
        XCTAssertNil(friday("diff tokyo tomorrow"))
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
