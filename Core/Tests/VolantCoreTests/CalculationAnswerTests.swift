import XCTest
@testable import VolantCore

final class CalculationAnswerTests: XCTestCase {
    private let october = ISO8601DateFormatter().date(from: "2026-10-02T09:00:00Z")!
    private let paris = TimeZone(identifier: "Europe/Paris")!
    private let english = Locale(identifier: "en_US")

    private func answers(_ query: String) -> [CalculationAnswer] {
        CalculationAnswer.answers(for: query, now: october, localZone: paris, locale: english)
    }

    func testTimeConversionSplitsTheAnswerFromItsDayContext() throws {
        let answer = try XCTUnwrap(answers("4pm   EST in CET").first)
        XCTAssertEqual(answer.input, "4pm EST in CET")
        XCTAssertEqual(answer.inputDetail, "Friday, October 2")
        XCTAssertEqual(answer.result, "10:00 PM CEST")
        XCTAssertEqual(answer.resultDetail, "Today")
        XCTAssertEqual(answer.copyText, "10:00 PM CEST")
    }

    func testLocalDestinationAndRolloverReadAsDayWords() throws {
        let local = try XCTUnwrap(answers("4pm in CET").first)
        XCTAssertEqual(local.result, "4:00 PM")
        XCTAssertEqual(local.resultDetail, "Your time · Today")
        XCTAssertEqual(local.copyText, "4:00 PM · your time")
        let late = try XCTUnwrap(answers("6pm PST in CET").first)
        XCTAssertEqual(late.result, "3:00 AM CEST")
        XCTAssertEqual(late.resultDetail, "Tomorrow")
        XCTAssertEqual(late.copyText, "3:00 AM CEST · tomorrow")
        XCTAssertEqual(try XCTUnwrap(answers("time in Tokyo").first).inputDetail, "Now")
    }

    func testExplicitDatesShowTheirYearOnlyWhenItDiffers() throws {
        XCTAssertEqual(try XCTUnwrap(answers("2027-01-04 9am EST in CET").first).inputDetail, "Monday, January 4, 2027")
        let later = try XCTUnwrap(answers("2026-10-05 9am EST in CET").first)
        XCTAssertEqual(later.inputDetail, "Monday, October 5")
        XCTAssertEqual(later.resultDetail, "Monday, October 5")
        XCTAssertEqual(later.copyText, "3:00 PM CEST · Oct 5, 2026")
        let rollover = try XCTUnwrap(answers("2026-12-31 3pm PST in CET").first)
        XCTAssertEqual(rollover.inputDetail, "Thursday, December 31")
        XCTAssertEqual(rollover.resultDetail, "Friday, January 1, 2027")
        XCTAssertEqual(try XCTUnwrap(answers("2026-10-03 9am EST in CET").first).resultDetail, "Tomorrow")
    }

    func testRelativeDayCardMatchesTheReferenceLayout() throws {
        let answer = try XCTUnwrap(answers("7:30pm tomorrow").first)
        XCTAssertEqual(answer.input, "7:30pm tomorrow")
        XCTAssertEqual(answer.inputDetail, "Saturday, October 3")
        XCTAssertEqual(answer.result, "Tomorrow at 7:30 PM")
        XCTAssertEqual(answer.resultDetail, "Saturday")
        XCTAssertEqual(answer.copyText, "Saturday, October 3 at 7:30 PM")
    }

    func testArithmeticReadsSmallWholeNumbersAsWords() throws {
        let sum = try XCTUnwrap(answers("2 + 2").first)
        XCTAssertEqual(sum.input, "2 + 2")
        XCTAssertNil(sum.inputDetail)
        XCTAssertEqual(sum.result, "4")
        XCTAssertEqual(sum.resultDetail, "Four")
        XCTAssertEqual(try XCTUnwrap(answers("1234 * 1000").first).resultDetail, "1,234,000")
        XCTAssertNil(try XCTUnwrap(answers("10 / 4").first).resultDetail)
    }

    func testTipAnswersTheTotalAndTagsTheTip() throws {
        let tip = try XCTUnwrap(answers("15% tip on 42").first)
        XCTAssertEqual(tip.result, "48.3")
        XCTAssertEqual(tip.resultDetail, "Tip 6.3")
        XCTAssertEqual(tip.copyText, "48.3")
        XCTAssertEqual(try XCTUnwrap(answers("52% of 900").first).resultDetail, "Four hundred sixty-eight")
    }

    func testUnitConversionNamesBothUnitsAndCopiesTheResult() throws {
        let answer = try XCTUnwrap(answers("5 km in mi").first)
        XCTAssertEqual(answer.input, "5 km")
        XCTAssertEqual(answer.inputDetail, "Kilometers")
        XCTAssertEqual(answer.resultDetail, "Miles")
        XCTAssertEqual(answer.copyText, answer.result)
        XCTAssertTrue(answer.result.hasSuffix(" mi"))
    }

    func testOrdinaryTextHasNoAnswer() {
        XCTAssertTrue(answers("Safari").isEmpty)
    }

    func testQuestionFramingIsIgnored() throws {
        for query in ["what is 5 + 5", "What's 5 + 5?", "whats 5 + 5", "calculate 5 + 5", "5 + 5 =", "5 + 5 = ", "5 + 5?"] {
            let answer = try XCTUnwrap(answers(query).first, query)
            XCTAssertEqual(answer.input, "5 + 5", query)
            XCTAssertEqual(answer.result, "10", query)
        }
        XCTAssertEqual(answers("what is 5 km in mi?").first?.result, "3.106856 mi")
        XCTAssertTrue(answers("what is").isEmpty)
        XCTAssertTrue(answers("what is love").isEmpty)
        XCTAssertTrue(answers("?").isEmpty)
        XCTAssertTrue(answers("=").isEmpty)
    }

    func testOpenParenthesesCloseAtTheEnd() throws {
        let answer = try XCTUnwrap(answers("2 * (3 + 4").first)
        XCTAssertEqual(answer.input, "2 * (3 + 4)")
        XCTAssertEqual(answer.result, "14")
        XCTAssertEqual(answers("sqrt(16").first?.input, "sqrt(16)")
        XCTAssertEqual(answers("((1 + 2) * 3").first?.result, "9")
        XCTAssertEqual(answers("2 * (3 + 4)").first?.input, "2 * (3 + 4)")
        XCTAssertTrue(answers("2 * (3 + 4))").isEmpty)
        XCTAssertTrue(answers("2 * (3 +").isEmpty)
        XCTAssertTrue(answers("sqrt(").isEmpty)
    }

    func testCountWordsAndNewUnitCards() throws {
        XCTAssertEqual(answers("2 dozen").first?.result, "24")
        XCTAssertEqual(answers("3 gross").first?.result, "432")
        XCTAssertEqual(answers("2 dozen + 3").first?.result, "27")
        let dozens = try XCTUnwrap(answers("30 in dozens").first)
        XCTAssertEqual(dozens.input, "30")
        XCTAssertNil(dozens.inputDetail)
        XCTAssertEqual(dozens.result, "2.5 dozen")
        XCTAssertEqual(dozens.resultDetail, "Dozen")
        XCTAssertEqual(dozens.swapQuery, "2.5 dozen in each")
        let light = try XCTUnwrap(answers("speed of light").first)
        XCTAssertEqual(light.inputDetail, "Speed of light")
        XCTAssertEqual(light.result, "299792458 m/s")
        let mach = try XCTUnwrap(answers("mach 2 in km/h").first)
        XCTAssertEqual(mach.inputDetail, "Mach (sea level, 15 °C)")
        XCTAssertEqual(answers("1 atm in pa").first?.resultDetail, "Pascals")
        XCTAssertEqual(answers("1 btu in j").first?.inputDetail, "British thermal units (IT)")
    }
}
