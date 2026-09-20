import XCTest

@testable import VolantCore

final class EmojiTests: XCTestCase {
    private let entries = [EmojiEntry(symbol: "A", name: "typeface"), EmojiEntry(symbol: "B", name: "grinning face"), EmojiEntry(symbol: "C", name: "face smiling"), EmojiEntry(symbol: "D", name: "cat")]
    func testPrefixRankingAndLimits() {
        XCTAssertEqual(EmojiIndex.search(" FACE ", limit: 10, entries: entries).map(\.symbol), ["B", "C", "A"])
        XCTAssertEqual(EmojiIndex.search("face", limit: 2, entries: entries).map(\.symbol), ["B", "C"])
        XCTAssertEqual(EmojiIndex.search("face", limit: 1, entries: entries).map(\.symbol), ["B"])
        XCTAssertTrue(EmojiIndex.search("face", limit: 0, entries: entries).isEmpty)
    }
    func testCatalogExcludesIncompleteEmojiAndRequestsColorPresentation() {
        XCTAssertNil(EmojiIndex.catalogEntry(symbol: "🇦", name: "regional indicator a"))
        XCTAssertNil(EmojiIndex.catalogEntry(symbol: "1", name: "digit one"))
        XCTAssertNil(EmojiIndex.catalogEntry(symbol: "\u{1F322}", name: "black droplet"))
        XCTAssertEqual(EmojiIndex.catalogEntry(symbol: "🇬🇧", name: "flag")?.symbol, "🇬🇧")
        XCTAssertEqual(EmojiIndex.catalogEntry(symbol: "1️⃣", name: "keycap")?.symbol, "1️⃣")
        XCTAssertEqual(EmojiIndex.catalogEntry(symbol: "❤", name: "heart")?.symbol, "❤️")
    }
    func testBrowsingAndEmptyResults() {
        XCTAssertEqual(EmojiIndex.search("", limit: Int.max, entries: entries), entries)
        XCTAssertEqual(EmojiIndex.search("", limit: 2, entries: entries), Array(entries.prefix(2)))
        XCTAssertTrue(EmojiIndex.search("unknown", entries: entries).isEmpty)
    }
}
