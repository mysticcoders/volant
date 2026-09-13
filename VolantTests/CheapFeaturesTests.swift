import XCTest
@testable import Volant

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

    func testShortcutQuicklinksPreserveInputAndRestrictActions() throws {
        let link = Quicklink(name: "capture", url: "shortcuts://run-shortcut?name=Capture%20Text&input=text&text={query}")
        let input = "tea & coffee #1 + 50% 📝\nnext?name=Other"
        let url = try XCTUnwrap(QuicklinkResolver.url(for: link, query: input))
        let items = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems)
        XCTAssertEqual(items.count, 3)
        XCTAssertEqual(items.first { $0.name == "name" }?.value, "Capture Text")
        XCTAssertEqual(items.first { $0.name == "text" }?.value, input)
        for valid in ["shortcuts://run-shortcut?name=Example", "shortcuts://run-shortcut?name=Example&input=clipboard"] {
            XCTAssertNotNil(QuicklinkResolver.url(for: Quicklink(name: "test", url: valid), query: ""))
        }
        for invalid in [
            "shortcuts://create-shortcut?name=Example",
            "shortcuts://x-callback-url/run-shortcut?name=Example",
            "shortcuts://run-shortcut?name=",
            "shortcuts://run-shortcut?name=One&name=Two",
            "shortcuts://run-shortcut?name=One&input=text",
            "shortcuts://run-shortcut?name=One&input=unknown",
            "shortcuts://run-shortcut?name=One&x-success=https://example.com",
            "shortcuts://run-shortcut/path?name=One",
            "shortcuts://run-shortcut?name=One#fragment"
        ] {
            XCTAssertNil(QuicklinkResolver.url(for: Quicklink(name: "test", url: invalid), query: ""), invalid)
        }
    }

    func testQuicklinkEncodesQueryAndRejectsSchemes() {
        let g = Quicklink(name: "Google", url: "https://www.google.com/search?q={query}")
        XCTAssertEqual(QuicklinkResolver.url(for: g, query: "volant launcher")?.absoluteString, "https://www.google.com/search?q=volant%20launcher")
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
