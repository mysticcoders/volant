import XCTest
@testable import Vey

final class CheapFeaturesTests: XCTestCase {
    func testSnippetPlaceholders() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let out = SnippetExpander.expand("Date {isodate} clip:{clipboard} id:{uuid}", now: now, clipboard: "X")
        XCTAssertTrue(out.hasPrefix("Date 2023-11-14 clip:X id:"))
        XCTAssertEqual(out.count, "Date 2023-11-14 clip:X id:".count + 36)
    }

    func testSnippetSearchExactKeywordFirst() {
        let s = [Snippet(name: "Signature", keyword: "sig", body: "a"), Snippet(name: "Sigh", keyword: "sigh", body: "b")]
        XCTAssertEqual(SnippetExpander.search(s, "sig").first?.name, "Signature")
        XCTAssertEqual(SnippetExpander.search(s, "sig").count, 2)
    }

    func testQuicklinkEncodesQueryAndRejectsSchemes() {
        let g = Quicklink(name: "Google", url: "https://www.google.com/search?q={query}")
        XCTAssertEqual(QuicklinkResolver.url(for: g, query: "vey launcher")?.absoluteString, "https://www.google.com/search?q=vey%20launcher")
        XCTAssertNil(QuicklinkResolver.url(for: Quicklink(name: "bad", url: "file:///etc/passwd"), query: ""))
        XCTAssertNil(QuicklinkResolver.url(for: Quicklink(name: "bad", url: "javascript:alert(1)"), query: ""))
        XCTAssertTrue(QuicklinkResolver.needsQuery(g))
    }

    func testMehAndHyperParse() {
        XCTAssertNotNil(KeyCombo(parsing: "meh+space"))
        XCTAssertNotNil(KeyCombo(parsing: "hyper+n"))
        XCTAssertNotEqual(KeyCombo(parsing: "meh+space"), KeyCombo(parsing: "hyper+space"))
    }

    func testOlderConfigWithoutNewSectionsStillLoads() throws {
        let prefs = try JSONDecoder().decode(Preferences.self, from: Data(#"{"summonHotKey":"cmd+space"}"#.utf8))
        XCTAssertEqual(prefs.quicklinks.first?.name, "Google")
        XCTAssertTrue(prefs.snippets.isEmpty)
        XCTAssertEqual(prefs.appearance.scale, 1.0)
    }
}
