import XCTest

@testable import VolantCore

/// A capital inside a run-together name starts a word, so acronym queries rank camelCase names
/// above the same letters written flat.
final class FuzzyMatcherCamelCaseTests: XCTestCase {
    func testCamelCaseWordStartCounts() throws {
        let camel = try XCTUnwrap(FuzzyMatcher.score(query: "vsc", candidate: "VisualStudioCode"))
        let flat = try XCTUnwrap(FuzzyMatcher.score(query: "vsc", candidate: "visualstudiocode"))
        XCTAssertGreaterThan(camel, flat)
    }
}
