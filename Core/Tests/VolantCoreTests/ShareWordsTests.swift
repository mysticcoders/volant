import XCTest
@testable import VolantCore

final class ShareWordsTests: XCTestCase {
    private let english = Locale(identifier: "en_US")

    private func result(_ query: String) -> String? {
        ShareWords.evaluate(query, locale: english)?.result
    }

    func testSharesAndMultiplesOfNumbers() {
        XCTAssertEqual(result("half of 30"), "15")
        XCTAssertEqual(result("a third of 90"), "30")
        XCTAssertEqual(result("two thirds of 12"), "8")
        XCTAssertEqual(result("a quarter of 200"), "50")
        XCTAssertEqual(result("three quarters of 80"), "60")
        XCTAssertEqual(result("double 21"), "42")
        XCTAssertEqual(result("twice 8"), "16")
        XCTAssertEqual(result("Triple 7"), "21")
        XCTAssertEqual(result("half of 30 + 10"), "20")
    }

    func testSharesOfMoneyAndDurations() {
        XCTAssertEqual(result("half of $80"), "$40.00")
        XCTAssertEqual(result("a third of 2 hours"), "40 minutes")
        XCTAssertEqual(result("10% of 1 hour"), "6 minutes")
        XCTAssertEqual(result("25% of 2h 30m"), "37 minutes 30 seconds")
        XCTAssertEqual(result("double 45 min"), "1 hour 30 minutes")
    }

    func testWordsWithoutAnAmountStaySearches() {
        for query in ["double commander", "half of", "half life", "twice", "a third of the way", "10% of everything"] {
            XCTAssertNil(ShareWords.evaluate(query, locale: english), query)
        }
        let paris = TimeZone(identifier: "Europe/Paris")!
        XCTAssertEqual(CalculationAnswer.answers(for: "half of 30", localZone: paris, locale: english).map(\.result), ["15"])
        XCTAssertEqual(CalculationAnswer.answers(for: "10% of 50", localZone: paris, locale: english).map(\.result), ["5"])
    }
}
