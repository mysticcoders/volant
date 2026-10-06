import XCTest
@testable import VolantCore

final class ClockSpanTests: XCTestCase {
    /// Tuesday, October 6, 2026, 2:15 PM in Paris (CEST).
    private let now = ISO8601DateFormatter().date(from: "2026-10-06T12:15:00Z")!
    private let paris = TimeZone(identifier: "Europe/Paris")!

    private func card(_ query: String, at moment: Date? = nil) -> [String?] {
        guard let a = DateCalculator.evaluate(query, now: moment ?? now, localZone: paris, locale: Locale(identifier: "en_US")) else { return [] }
        return [a.result, a.inputDetail, a.copyText]
    }

    func testSpansBetweenClockTimes() {
        XCTAssertEqual(card("9am to 5:30pm"), ["8 hours 30 minutes", "9:00 AM to 5:30 PM", "8 hours 30 minutes"])
        XCTAssertEqual(card("from 9am until noon"), ["3 hours", "9:00 AM to Noon", "3 hours"])
        XCTAssertEqual(card("between 9am and 5pm").first, "8 hours")
        XCTAssertEqual(card("09:15 to 17:45").first, "8 hours 30 minutes")
        XCTAssertEqual(card("9am till 9:05am").first, "5 minutes")
        XCTAssertEqual(card("9am to 5:30pm in hours").first, "8.5 hours")
        XCTAssertEqual(card("9am to 5:30pm in minutes").first, "510 minutes")
    }

    func testSpansWrapPastMidnight() {
        XCTAssertEqual(card("3pm - 9am"), ["18 hours", "3:00 PM to 9:00 AM · Overnight", "18 hours"])
        XCTAssertEqual(card("3pm-9am").first, "18 hours")
        XCTAssertEqual(card("10pm to 6am").first, "8 hours")
        XCTAssertEqual(card("11:30pm to midnight").first, "30 minutes")
    }

    func testSpansCountWallClockTimeAcrossDaylightSaving() {
        let fallBack = ISO8601DateFormatter().date(from: "2026-10-25T08:00:00Z")!
        XCTAssertEqual(card("1am to 4am", at: fallBack).first, "3 hours")
    }

    func testNoSpanForEqualOrMissingTimes() {
        XCTAssertEqual(card("9am to 9am"), [])
        XCTAssertEqual(card("9 to 5"), [])
        XCTAssertEqual(card("9am to lunch"), [])
    }

    func testScaledDurations() {
        XCTAssertEqual(card("1h 30m * 3").first, "4 hours 30 minutes")
        XCTAssertEqual(card("1h 30m x 3").first, "4 hours 30 minutes")
        XCTAssertEqual(card("3 * 45 min").first, "2 hours 15 minutes")
        XCTAssertEqual(card("90 min * 3").first, "4 hours 30 minutes")
        XCTAssertEqual(card("2h / 4").first, "30 minutes")
        XCTAssertEqual(card("1h 30m * 3 in hours").first, "4.5 hours")
        XCTAssertEqual(card("2h 20min + 55min * 2").first, "4 hours 10 minutes")
        XCTAssertEqual(card("2h / 0"), [])
        XCTAssertEqual(card("2h 20min + 55min").first, "3 hours 15 minutes")
    }

    func testHoursAndMinutesAfterAClockTime() {
        XCTAssertEqual(card("10:30 + 2:45"), ["1:15 PM", "10:30 AM", "1:15 PM"])
        XCTAssertEqual(card("3:45pm - 1:30").first, "2:15 PM")
        XCTAssertEqual(card("11pm + 1:30").first, "12:30 AM")
        XCTAssertEqual(card("3:45pm + 5").first, "8:45 PM")
        XCTAssertEqual(card("10:30 + 2:5"), [])
    }

    func testNoonAndMidnightAsClockTimes() {
        XCTAssertEqual(card("noon + 3").first, "3:00 PM")
        XCTAssertEqual(card("midnight + 90 min").first, "1:30 AM")
        XCTAssertEqual(card("noon to 1:30pm").first, "1 hour 30 minutes")

        let january = ISO8601DateFormatter().date(from: "2026-01-15T12:00:00Z")!
        func time(_ query: String) -> TimeCalculator.Result? {
            TimeCalculator.evaluate(query, now: january, localZone: paris, locale: Locale(identifier: "en_US"))
        }
        XCTAssertEqual(time("noon in tokyo")?.date, ISO8601DateFormatter().date(from: "2026-01-15T03:00:00Z"))
        XCTAssertEqual(time("noon tokyo in london")?.text, "3:00 AM in London")
        XCTAssertEqual(time("midnight PST in London")?.text, "8:00 AM in London")
        XCTAssertEqual(time("noon tomorrow")?.headline, "Tomorrow at noon")
        XCTAssertEqual(time("noon in tokyo"), time("12pm in tokyo"))
    }
}
