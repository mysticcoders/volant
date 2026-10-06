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

    func testNextAndThisWeekday() {
        XCTAssertEqual(card("next friday"), ["Friday, October 9", "In 3 days", "Friday, October 9"])
        XCTAssertEqual(card("this friday").first, "Friday, October 9")
        XCTAssertEqual(card("next tuesday"), ["Tuesday, October 13", "In 7 days", "Tuesday, October 13"])
        XCTAssertEqual(card("this tuesday").first, "Tuesday, October 6")
        XCTAssertEqual(card("days until next monday").first, "6 days")
        XCTAssertEqual(card("next friday + 1 week").first, "Friday, October 16")
    }

    func testLastAndAfterNextAlone() {
        XCTAssertEqual(card("last friday"), ["Friday, October 2", "4 days ago", "Friday, October 2"])
        XCTAssertEqual(card("last tuesday").first, "Tuesday, September 29")
        XCTAssertEqual(card("friday after next"), ["Friday, October 16", "In 10 days", "Friday, October 16"])
        XCTAssertEqual(card("days since last monday").first, "1 day")
    }

    func testNamedHolidays() {
        XCTAssertEqual(card("days until christmas"), ["80 days", "Friday, December 25", "80 days"])
        XCTAssertEqual(card("days until Christmas Eve").first, "79 days")
        XCTAssertEqual(card("days until halloween").first, "25 days")
        XCTAssertEqual(card("days since new year's day").first, "278 days")
        XCTAssertEqual(card("days until easter"), ["173 days", "Sunday, March 28, 2027", "173 days"])
        XCTAssertEqual(card("thanksgiving + 1").first, "Friday, November 27")
        XCTAssertEqual(card("christmas 2027 + 0").first, "Saturday, December 25, 2027")
        XCTAssertEqual(card("days until 4th of July").first, "271 days")
        XCTAssertEqual(DateCalculator.easter(2026).month * 100 + DateCalculator.easter(2026).day, 405)
        XCTAssertEqual(DateCalculator.easter(2024).month * 100 + DateCalculator.easter(2024).day, 331)
        XCTAssertEqual(DateCalculator.easter(2000).month * 100 + DateCalculator.easter(2000).day, 423)
        XCTAssertEqual(DateCalculator.Holiday.thanksgiving.date(in: 2026).day, 26)
        XCTAssertEqual(DateCalculator.Holiday.thanksgiving.date(in: 2027).day, 25)
    }

    private func card(_ query: String, region: String) -> [String?] {
        guard let a = DateCalculator.evaluate(query, now: now, localZone: paris, locale: Locale(identifier: region)) else { return [] }
        return [a.result, a.inputDetail, a.copyText]
    }

    func testWorkdaysSkipTheRegionsPublicHolidays() {
        XCTAssertEqual(card("workdays until Dec 25"), ["54 workdays", "Friday, December 25", "54 workdays"])
        XCTAssertEqual(answer("workdays until Dec 25")?.inputDetail, "Skips US holidays")
        XCTAssertEqual(card("business days until christmas").first, "54 workdays")
        XCTAssertEqual(card("in 10 workdays"), ["Wednesday, October 21", "In 15 days", "Wednesday, October 21"])
        XCTAssertEqual(answer("in 10 workdays")?.inputDetail, "Skips US holidays")
        XCTAssertEqual(card("10 working days from now").first, "Wednesday, October 21")
        XCTAssertEqual(card("5 business days ago").first, "Tuesday, September 29")
        XCTAssertEqual(card("today + 10 workdays").first, "Wednesday, October 21")
        XCTAssertEqual(card("workdays between 2026-12-24 and 2027-01-04").first, "5 workdays")
        XCTAssertEqual(card("workdays until tomorrow").first, "1 workday")
    }

    func testWorkdaysWithoutRulesCountWeekendsOnly() {
        XCTAssertEqual(card("workdays until Dec 25", region: "en_JP"), ["58 workdays", "Weekends only", "58 workdays"])
        XCTAssertEqual(card("in 10 workdays", region: "en_JP").first, "Tuesday, October 20")
        XCTAssertEqual(card("workdays between 2026-12-24 and 2027-01-04", region: "en_JP").first, "7 workdays")
        XCTAssertEqual(card("workdays between 2026-12-24 and 2027-01-04", region: "en_GB"), ["4 workdays", "Skips UK holidays", "4 workdays"])
    }

    /// Official 2026 and 2027 lists: OPM federal holidays, GOV.UK bank holidays (England and Wales),
    /// German national and Canadian federal holidays.
    func testPublicHolidayRulesMatchPublishedLists() {
        func list(_ region: String, _ year: Int) -> [Int] { PublicHolidays.holidays(region, year).sorted() }
        XCTAssertEqual(list("US", 2026), [20260101, 20260119, 20260216, 20260525, 20260619, 20260703, 20260907, 20261012,
                                          20261111, 20261126, 20261225])
        XCTAssertEqual(list("GB", 2026), [20260101, 20260403, 20260406, 20260504, 20260525, 20260831, 20261225, 20261228])
        XCTAssertEqual(list("GB", 2027).suffix(2), [20271227, 20271228])
        XCTAssertEqual(list("DE", 2026), [20260101, 20260403, 20260406, 20260501, 20260514, 20260525, 20261003, 20261225, 20261226])
        XCTAssertTrue(list("CA", 2026).contains(20260518), "Victoria Day is the Monday before May 25")
        XCTAssertTrue(list("CA", 2026).contains(20260930))
        XCTAssertTrue(PublicHolidays.isHoliday(year: 2021, month: 12, day: 31, region: "US"), "New Year's Day 2022 fell on Saturday")
        XCTAssertFalse(PublicHolidays.isHoliday(year: 2026, month: 12, day: 25, region: "JP"))
    }

    func testMoreNamedHolidays() {
        XCTAssertEqual(card("days until memorial day"), ["237 days", "Monday, May 31, 2027", "237 days"])
        XCTAssertEqual(card("days until mother's day").first, "215 days")
        XCTAssertEqual(card("days until good friday").first, "171 days")
        XCTAssertEqual(card("days until boxing day").first, "81 days")
        XCTAssertEqual(card("labor day 2027 + 0").first, "Monday, September 6, 2027")
        XCTAssertEqual(card("fathers day 2027 + 0").first, "Sunday, June 20, 2027")
        XCTAssertEqual(card("easter monday 2027 + 0").first, "Monday, March 29, 2027")
    }

    func testSummedDurations() {
        XCTAssertEqual(card("2h 20min + 55min"), ["3 hours 15 minutes", nil, "3 hours 15 minutes"])
        XCTAssertEqual(card("2h 20min + 55min in hours").first, "3.25 hours")
        XCTAssertEqual(card("1h 30m - 45m in minutes").first, "45 minutes")
        XCTAssertEqual(card("2h 20min in minutes").first, "140 minutes")
        XCTAssertEqual(card("2 days 3 hours").first, "2 days 3 hours")
        XCTAssertEqual(card("1 hour + 1 hour in hours").first, "2 hours")
        XCTAssertEqual(card("90 sec + 30 sec to timespan").first, "2 minutes")
        for query in ["90 min in h", "1h - 2h", "2h + 3 months", "2h +", "+ 2h 30m", "2h 20min + banana"] {
            XCTAssertNil(answer(query), query)
        }
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

    func testWeekdayOfADate() {
        XCTAssertEqual(card("what day was 2000-01-01"), ["Saturday", "Saturday, January 1, 2000", "Saturday"])
        XCTAssertEqual(card("what day is christmas"), ["Friday", "Friday, December 25", "Friday"])
        XCTAssertEqual(card("what day was christmas"), ["Thursday", "Thursday, December 25, 2025", "Thursday"])
        XCTAssertEqual(card("What day of the week is Dec 25 2030").first, "Wednesday")
        XCTAssertEqual(card("what weekday will be March 1st 2027").first, "Monday")
        XCTAssertEqual(card("what day is it"), ["Tuesday", "Tuesday, October 6", "Tuesday"])
        XCTAssertEqual(card("what day is 2028-02-29").first, "Tuesday")
        XCTAssertNil(answer("what day is good"))
        XCTAssertNil(answer("what day"))
    }

    func testISOWeekNumber() {
        XCTAssertEqual(card("week number"), ["Week 41", "Monday, October 5 to Sunday, October 11", "Week 41"])
        XCTAssertEqual(answer("week number")?.inputDetail, "ISO 8601")
        XCTAssertEqual(card("week of the year").first, "Week 41")
        XCTAssertEqual(card("what week is it").first, "Week 41")
        XCTAssertEqual(card("week number of Dec 25").first, "Week 52")
        XCTAssertEqual(card("week number of Jan 1 2027"), ["Week 53 of 2026", "Monday, December 28 to Sunday, January 3, 2027", "Week 53 of 2026"])
        XCTAssertEqual(card("week number 2024-12-30").first, "Week 1 of 2025")
        XCTAssertNil(answer("week number of"))
        XCTAssertNil(answer("week number of nothing"))
    }

    func testDayOfYear() {
        XCTAssertEqual(card("day of year"), ["Day 279", "86 days left in 2026", "Day 279"])
        XCTAssertEqual(card("day of the year Dec 31").first, "Day 365")
        XCTAssertEqual(card("day number of 2028-12-31"), ["Day 366", "0 days left in 2028", "Day 366"])
        XCTAssertEqual(answer("day of the year Dec 31")?.inputDetail, "Thursday, December 31")
    }

    func testDaysInAMonthOrYear() {
        XCTAssertEqual(card("days in february"), ["28 days", "February 2026", "28 days"])
        XCTAssertEqual(card("days in Feb 2028"), ["29 days", "February 2028", "29 days"])
        XCTAssertEqual(card("days in 2028"), ["366 days", "2028", "366 days"])
        XCTAssertEqual(card("days in 1900").first, "365 days")
        XCTAssertEqual(card("days in this month"), ["31 days", "October 2026", "31 days"])
        XCTAssertEqual(card("days in this year").first, "365 days")
        XCTAssertNil(answer("days in 2 weeks"))
        XCTAssertNil(answer("days in feb 28"))
        XCTAssertNil(answer("days in paris"))
    }

    func testLeapYears() {
        XCTAssertEqual(card("is 2028 a leap year"), ["Yes", "2028 has 366 days", "2028 is a leap year"])
        XCTAssertEqual(card("is 2027 a leap year"), ["No", "The next leap year is 2028", "2027 is not a leap year"])
        XCTAssertEqual(card("is it a leap year").first, "No")
        XCTAssertEqual(card("is this year a leap year").last, "2026 is not a leap year")
        XCTAssertEqual(card("2000 leap year").first, "Yes")
        XCTAssertEqual(card("1900 leap year"), ["No", "The next leap year is 1904", "1900 is not a leap year"])
        XCTAssertEqual(card("next leap year"), ["2028", "Tuesday, February 29, 2028", "2028"])
        XCTAssertNil(answer("is 28 a leap year"))
    }

    func testAgeFromABirthdate() {
        XCTAssertEqual(card("age 1985-04-12"), ["41 years", "Next birthday in 188 days", "41 years"])
        XCTAssertEqual(answer("age 1985-04-12")?.inputDetail, "Born Friday, April 12, 1985")
        XCTAssertEqual(card("age April 12 1985").first, "41 years")
        XCTAssertEqual(card("age 1985-04-12 on Jan 1 2030"), ["44 years", "On Tuesday, January 1, 2030", "44 years"])
        XCTAssertEqual(card("age 1985-10-06"), ["41 years", "Birthday today", "41 years"])
        XCTAssertEqual(card("age 1985-10-07"), ["40 years", "Next birthday in 1 day", "40 years"])
        XCTAssertEqual(card("age 2026-01-01").first, "0 years")
        XCTAssertEqual(card("age 2000-02-29 on 2001-02-28").first, "1 year", "a February 29 birthday falls on February 28 in common years")
        XCTAssertEqual(card("age 2000-02-29 on 2004-02-29").first, "4 years")
        XCTAssertNil(answer("age April 12"), "a birthdate needs its year")
        XCTAssertNil(answer("age 2030-01-01"), "a birthdate cannot be in the future")
        XCTAssertNil(answer("age of empires"))
    }

    func testDaysBetweenTwoDatesAsSubtraction() {
        XCTAssertEqual(card("Dec 25 - Oct 6"), ["80 days", "Tuesday, October 6 to Friday, December 25", "80 days"])
        XCTAssertEqual(card("Oct 6 - Dec 25").first, "-80 days")
        XCTAssertEqual(card("2027-01-01 - today").first, "87 days")
        XCTAssertEqual(card("christmas - thanksgiving").first, "29 days")
        XCTAssertEqual(card("Dec 25 - 5").first, "Sunday, December 20", "a plain number still means days")
        XCTAssertEqual(card("today - 3 days").first, "Saturday, October 3")
    }

    func testTimeAloneIsTheClock() {
        XCTAssertEqual(card("time"), card("now"))
        XCTAssertEqual(card("Time").first, "2:15 PM")
        XCTAssertNil(answer("time machine"))
    }

    func testWorkHoursAndWorkdaysInAPeriod() {
        XCTAssertEqual(card("workhours in 2023"), ["1,992 hours", "249 workdays", "1,992 hours"])
        XCTAssertEqual(answer("workhours in 2023")?.inputDetail, "Skips US holidays")
        XCTAssertEqual(card("work hours in 2023").first, "1,992 hours")
        XCTAssertEqual(card("workdays in 2027"), ["249 workdays", "1,992 work hours", "249 workdays"])
        XCTAssertEqual(card("workdays in november").first, "19 workdays")
        XCTAssertEqual(card("workhours in May 2027").first, "160 hours")
        XCTAssertEqual(card("workdays this month").first, "21 workdays")
        XCTAssertEqual(card("business days next year").first, "249 workdays")
        XCTAssertNil(answer("workhours in tokyo"))
        XCTAssertNil(answer("workdays in 20000"))
        let germany = DateCalculator.evaluate("workdays in 2027", now: now, localZone: paris, locale: Locale(identifier: "de_DE"))
        XCTAssertEqual(germany?.inputDetail, "Skips German holidays")
    }

    func testHoursInEightHourWorkdays() {
        XCTAssertEqual(card("55h in workdays"), ["6.875 workdays", "6 workdays 7 hours", "6.875 workdays"])
        XCTAssertEqual(answer("55h in workdays")?.inputDetail, "8-hour days")
        XCTAssertEqual(card("8 hours in workdays").first, "1 workday")
        XCTAssertEqual(card("2h 30min in workdays"), ["0.3125 workdays", "2 hours 30 minutes", "0.3125 workdays"])
        XCTAssertEqual(card("3 workdays in hours").first, "24 hours")
        XCTAssertEqual(card("1.5 workdays in minutes").first, "720 minutes")
        XCTAssertNil(answer("0h in workdays"))
        XCTAssertNil(answer("3 weeks in workdays"))
        XCTAssertNil(answer("2 days in workdays"))
    }
}
