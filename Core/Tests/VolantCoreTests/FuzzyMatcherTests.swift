import XCTest

@testable import VolantCore

final class FuzzyMatcherTests: XCTestCase {
    func testPrefixBeatsScattered() {
        let prefix = FuzzyMatcher.score(query: "saf", candidate: "Safari")!
        let scattered = FuzzyMatcher.score(query: "saf", candidate: "System Alarm Factory")!
        XCTAssertGreaterThan(prefix, scattered)
    }

    func testNoMatchReturnsNil() {
        XCTAssertNil(FuzzyMatcher.score(query: "xyz", candidate: "Safari"))
    }

    func testCaseInsensitive() {
        XCTAssertNotNil(FuzzyMatcher.score(query: "OBS", candidate: "obsidian"))
    }

    func testAcronymGetsWordStartBonus() {
        let acronym = FuzzyMatcher.score(query: "vsc", candidate: "Visual Studio Code")!
        let plain = FuzzyMatcher.score(query: "vsc", candidate: "vascular")!
        XCTAssertGreaterThan(acronym, plain)
    }
}
