import XCTest
@testable import VolantCore

final class PercentQuestionsTests: XCTestCase {
    private func card(_ query: String) -> [String?] {
        guard let a = PercentQuestions.evaluate(query, locale: Locale(identifier: "en_US")) else { return [] }
        return [a.result, a.resultDetail, a.copyText]
    }

    func testWhatShareOneNumberIsOfAnother() {
        XCTAssertEqual(card("20 is what percent of 80"), ["25%", "20 of 80", "25%"])
        XCTAssertEqual(card("20 is what % of 80"), ["25%", "20 of 80", "25%"])
        XCTAssertEqual(card("What percentage is 20 of 80?"), ["25%", "20 of 80", "25%"])
        XCTAssertEqual(card("what % of 80 is 20"), ["25%", "20 of 80", "25%"])
        XCTAssertEqual(card("1 is what pct of 3").first, "33.3333%")
        XCTAssertEqual(card("90 is what percent of 60").first, "150%")
        XCTAssertEqual(card("1,000 is what percent of 4 * 1000").first, "25%")
    }

    func testTheWholeFromAPart() {
        XCTAssertEqual(card("20 is 25% of what"), ["80", "25% of 80 is 20", "80"])
        XCTAssertEqual(card("20 is 25 percent of what").first, "80")
        XCTAssertEqual(card("15 is 30 % of what").first, "50")
    }

    func testPercentChange() {
        XCTAssertEqual(card("increase from 50 to 75"), ["+50%", "Increase of 25", "+50%"])
        XCTAssertEqual(card("decrease from 75 to 50"), ["-33.3333%", "Decrease of 25", "-33.3333%"])
        XCTAssertEqual(card("increase from 75 to 50").first, "-33.3333%")
        XCTAssertEqual(card("percent change from 50 to 75").first, "+50%")
        XCTAssertEqual(card("% change from 200 to 150").first, "-25%")
        XCTAssertEqual(card("50 to 75 percent change").first, "+50%")
        XCTAssertEqual(card("from 50 to 75 % change").first, "+50%")
        XCTAssertEqual(card("change from 40 to 40"), ["0%", "No change", "0%"])
        XCTAssertEqual(card("change from -50 to -25").first, "+50%")
    }

    func testFractionsAsPercentages() {
        XCTAssertEqual(card("3/4 in percent"), ["75%", nil, "75%"])
        XCTAssertEqual(card("1/3 as a percentage").first, "33.3333%")
        XCTAssertEqual(card("0.125 to percent").first, "12.5%")
        XCTAssertEqual(card("2 in %").first, "200%")
    }

    func testNoAnswerForWhatCannotBeComputed() {
        XCTAssertEqual(card("20 is what percent of 0"), [])
        XCTAssertEqual(card("20 is 0% of what"), [])
        XCTAssertEqual(card("increase from 0 to 10"), [])
        XCTAssertEqual(card("change from apples to pears"), [])
        XCTAssertEqual(card("percent"), [])
        XCTAssertEqual(card("10 percent of 50"), [])
        XCTAssertEqual(card("climate change"), [])
    }

    func testPercentWordsReadAsPercentInArithmetic() throws {
        let english = Locale(identifier: "en_US")
        XCTAssertEqual(try XCTUnwrap(Calculator.evaluate("10 percent of 50", locale: english)), 5, accuracy: 1e-9)
        XCTAssertEqual(try XCTUnwrap(Calculator.evaluate("20 pct off 80", locale: english)), 64, accuracy: 1e-9)
        XCTAssertEqual(try XCTUnwrap(Calculator.evaluate("100 + 10 percent", locale: english)), 110, accuracy: 1e-9)
        XCTAssertNil(Calculator.evaluate("percentage", locale: english))
    }

    func testAnswersListPercentQuestions() {
        let answers = CalculationAnswer.answers(for: "20 is what percent of 80", locale: Locale(identifier: "en_US"))
        XCTAssertEqual(answers.map(\.result), ["25%"])
    }
}
