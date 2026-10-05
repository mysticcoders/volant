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
}
