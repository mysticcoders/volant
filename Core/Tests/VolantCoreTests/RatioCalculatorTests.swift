import XCTest
@testable import VolantCore

final class RatioCalculatorTests: XCTestCase {
    private let english = Locale(identifier: "en_US")

    private func card(_ query: String, locale: Locale? = nil) -> [String?] {
        guard let answer = RatioCalculator.evaluate(query, locale: locale ?? english) else { return [] }
        return [answer.result, answer.resultDetail, answer.copyText]
    }

    func testRatioPhrasingsAnswerTheQuotient() {
        XCTAssertEqual(card("ratio of 3 to 5"), ["0.6", "60% · 3:5", "0.6"])
        XCTAssertEqual(card("ratio 16:9"), ["1.7777777778", "177.78% · 16:9", "1.7777777778"])
        XCTAssertEqual(card("1920:1080 ratio").last, "1.7777777778")
        XCTAssertEqual(card("1920:1080 ratio")[1], "177.78% · 16:9")
        XCTAssertEqual(card("4 to 6 ratio")[1], "66.67% · 2:3")
        XCTAssertEqual(card("ratio of 1.5 to 4.5")[1], "33.33% · 1:3")
        XCTAssertEqual(card("ratio of 2,5 to 5", locale: Locale(identifier: "de_DE")).first, "0,5")
    }

    func testRatiosNeedTheWordAndAValidDivisor() {
        XCTAssertEqual(card("3:45"), [])
        XCTAssertEqual(card("3 to 5"), [])
        XCTAssertEqual(card("ratio of 3 to 0"), [])
        XCTAssertEqual(card("ratio of apples to oranges"), [])
        XCTAssertEqual(card("ratio"), [])
    }

    func testCalculatorCardsIncludeRatiosButNotClockTimes() {
        let paris = TimeZone(identifier: "Europe/Paris")!
        let ratio = CalculationAnswer.answers(for: "ratio of 3 to 5", localZone: paris, locale: english)
        XCTAssertEqual(ratio.map(\.result), ["0.6"])
        let clock = CalculationAnswer.answers(for: "16:9 ratio", localZone: paris, locale: english)
        XCTAssertEqual(clock.map(\.result), ["1.7777777778"])
    }
}
