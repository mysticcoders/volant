import XCTest
@testable import VolantCore

final class DateCalculatorTests: XCTestCase {
    /// Tuesday, October 6, 2026, 2:15 PM in Paris (CEST).
    private let now = ISO8601DateFormatter().date(from: "2026-10-06T12:15:00Z")!
    private let paris = TimeZone(identifier: "Europe/Paris")!

    private func answer(_ query: String, at moment: Date? = nil) -> CalculationAnswer? {
        DateCalculator.evaluate(query, now: moment ?? now, localZone: paris, locale: Locale(identifier: "en_US"))
    }

    private func card(_ query: String) -> [String?] {
        guard let a = answer(query) else { return [] }
        return [a.result, a.resultDetail, a.copyText]
    }

    func testDayWordsOnTheirOwn() {
        XCTAssertEqual(card("now"), ["2:15 PM", "Tuesday, October 6", "Tuesday, October 6 at 2:15 PM"])
        XCTAssertEqual(card("today"), ["Tuesday, October 6", "Today", "Tuesday, October 6"])
        XCTAssertEqual(card("Tomorrow"), ["Wednesday, October 7", "Tomorrow", "Wednesday, October 7"])
        XCTAssertEqual(card("yesterday"), ["Monday, October 5", "Yesterday", "Monday, October 5"])
    }

    func testCountingDaysUntilSinceAndBetween() {
        XCTAssertEqual(card("days until 31 Mar"), ["176 days", "Wednesday, March 31, 2027", "176 days"])
        XCTAssertEqual(card("days until Dec 25th"), ["80 days", "Friday, December 25", "80 days"])
        XCTAssertEqual(card("days until today").first, "0 days")
        XCTAssertEqual(card("days until tomorrow").first, "1 day")
        XCTAssertEqual(card("days since Jan 1"), ["278 days", "Thursday, January 1", "278 days"])
        XCTAssertEqual(card("days since Dec 25").first, "285 days")
        XCTAssertEqual(card("weeks until 2026-12-25").first, "11 weeks 3 days")
        XCTAssertEqual(card("weeks until 2026-10-20").first, "2 weeks")
        XCTAssertEqual(card("days until 2025-01-01").first, "643 days ago")
        XCTAssertEqual(card("days between Jan 1 and Mar 1").first, "59 days")
        XCTAssertEqual(card("days between 2028-01-01 and 2028-03-01").first, "60 days")
        XCTAssertEqual(card("days between Jan 1 and Mar 1")[1], "Thursday, January 1 to Sunday, March 1")
    }

    func testOffsetsFromNow() {
        XCTAssertEqual(card("in 3 weeks"), ["Tuesday, October 27", "In 21 days", "Tuesday, October 27"])
        XCTAssertEqual(card("10 days from now").first, "Friday, October 16")
        XCTAssertEqual(card("35 days ago"), ["Tuesday, September 1", "35 days ago", "Tuesday, September 1"])
        XCTAssertEqual(card("in a week").first, "Tuesday, October 13")
        XCTAssertEqual(card("in 2 months").first, "Sunday, December 6")
        XCTAssertEqual(card("in 1 year").first, "Wednesday, October 6, 2027")
        XCTAssertEqual(card("in 4 hours"), ["6:15 PM", "Today", "6:15 PM"])
        XCTAssertEqual(card("in 12 hours"), ["2:15 AM", "Tomorrow", "Wednesday, October 7 at 2:15 AM"])
        XCTAssertEqual(card("90 minutes ago").first, "12:45 PM")
    }

    func testWeekdayInWeeksUsesThatWeek() {
        XCTAssertEqual(card("monday in 3 weeks"), ["Monday, October 26", "In 20 days", "Monday, October 26"])
        XCTAssertEqual(card("sunday in 1 week").first, "Sunday, October 18")
        XCTAssertEqual(card("tuesday in a week").first, "Tuesday, October 13")
        XCTAssertNil(answer("monday in 10 days"))
    }

    func testDateArithmeticCountsCalendarDays() {
        XCTAssertEqual(card("August 5 + 5"), ["Monday, August 10", "57 days ago", "Monday, August 10"])
        XCTAssertEqual(answer("August 5 + 5")?.inputDetail, "Wednesday, August 5")
        XCTAssertEqual(card("5 Aug 2027 - 2 weeks").first, "Thursday, July 22, 2027")
        XCTAssertEqual(card("today + 90 days").first, "Monday, January 4, 2027")
        XCTAssertEqual(card("2028-01-31 + 1 month").first, "Tuesday, February 29, 2028")
        XCTAssertEqual(card("2027-02-28 + 1 day").first, "Monday, March 1, 2027")
        XCTAssertEqual(card("friday + 1 week").first, "Friday, October 16")
    }

    func testCalendarDaysIgnoreDaylightSavingWhileHoursCountElapsedTime() {
        let beforeChange = ISO8601DateFormatter().date(from: "2026-10-24T22:00:00Z")!
        XCTAssertEqual(answer("in 1 day", at: beforeChange)?.result, "Monday, October 26")
        XCTAssertEqual(answer("in 4 hours", at: beforeChange)?.result, "3:00 AM")
        XCTAssertEqual(answer("in 24 hours", at: beforeChange)?.result, "11:00 PM")
    }

    func testClockArithmeticCountsHours() {
        XCTAssertEqual(card("3:45pm + 5"), ["8:45 PM", "Today", "8:45 PM"])
        XCTAssertEqual(answer("3:45pm + 5")?.inputDetail, "3:45 PM")
        XCTAssertEqual(card("9am + 90 min").first, "10:30 AM")
        XCTAssertEqual(card("10:00 pm + 3"), ["1:00 AM", "Tomorrow", "Wednesday, October 7 at 1:00 AM"])
        XCTAssertEqual(card("14:00 - 30 min").first, "1:30 PM")
        XCTAssertEqual(card("11 am + 1").first, "Noon")
    }

    func testTimespans() {
        XCTAssertEqual(card("145 mins to timespan"), ["2 hours 25 minutes", nil, "2 hours 25 minutes"])
        XCTAssertEqual(card("100000 s as duration").first, "1 day 3 hours 46 minutes 40 seconds")
        XCTAssertEqual(card("1.5 hours in timespan").first, "1 hour 30 minutes")
        XCTAssertEqual(card("3 days to time span").first, "3 days")
        XCTAssertEqual(card("61 min to timespan").first, "1 hour 1 minute")
        XCTAssertNil(answer("0 min to timespan"))
    }

    func testISOTimestampsShowInLocalTime() {
        XCTAssertEqual(card("2024-03-15T14:30:00Z"), ["3:30 PM", "Friday, March 15, 2024", "Friday, March 15, 2024 at 3:30 PM"])
        XCTAssertEqual(answer("2024-03-15T14:30:00Z")?.inputDetail, "935 days ago")
        XCTAssertEqual(card("2026-10-06T09:00:00-04:00").first, "3:00 PM")
        XCTAssertEqual(card("2026-10-06t13:15:00.250z").first, "3:15 PM")
        XCTAssertEqual(card("2026-10-06 13:15:00Z").first, "3:15 PM")
        XCTAssertEqual(card("2026-10-07T08:00"), ["8:00 AM", "Wednesday, October 7", "Wednesday, October 7 at 8:00 AM"])
        XCTAssertEqual(answer("2026-10-07T08:00")?.inputDetail, "Tomorrow")
        XCTAssertNil(answer("2026-13-07T08:00:00Z"))
        XCTAssertNil(answer("2026-10-07T25:00"))
    }

    func testUnixTime() {
        XCTAssertEqual(card("unix 1700000000"), ["11:13 PM", "Tuesday, November 14, 2023", "Tuesday, November 14, 2023 at 11:13 PM"])
        XCTAssertEqual(answer("1700000000 unix")?.inputDetail, "Seconds")
        XCTAssertEqual(card("epoch 1700000000000").first, "11:13 PM")
        XCTAssertEqual(answer("epoch 1700000000000")?.inputDetail, "Milliseconds")
        XCTAssertEqual(card("unix now"), ["1791288900", "Seconds since 1970", "1791288900"])
        XCTAssertEqual(card("now in unix").first, "1791288900")
        XCTAssertNil(answer("unix 12345"))
        XCTAssertNil(answer("unix abc"))
    }

    func testNeverAnswersOrdinaryOrAmbiguousText() {
        for query in ["Safari", "2 + 2", "5 - 3", "now playing", "today show", "12/25 + 5", "days until", "days until someday",
                      "in 3 parsecs", "in 1.5 days", "Feb 30 + 1", "13pm + 1", "3:75pm + 1", "monday in", "3 weeks",
                      "ago", "in", "days between Jan 1", "145 mins to banana", "August + 5", "tomorrow + 2 hours"] {
            XCTAssertNil(answer(query), query)
        }
    }

    func testCardOrderPutsDatesAfterTimeAndBeforeArithmetic() {
        let answers = CalculationAnswer.answers(for: "today", now: now, localZone: paris, locale: Locale(identifier: "en_US"))
        XCTAssertEqual(answers.map(\.result), ["Tuesday, October 6"])
        XCTAssertEqual(CalculationAnswer.answers(for: "2 + 2", now: now, localZone: paris).map(\.result), ["4"])
    }
}
