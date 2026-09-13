import XCTest
@testable import Volant

final class MarkdownBlocksTests: XCTestCase {
    func testCodeBlockCopiesWithoutFences() {
        let md = "# Title\n\nSome text\n\n```bash\ncurl -s https://example.com | jq .\n```\n"
        let blocks = MarkdownBlocks.parse(md)
        XCTAssertEqual(blocks.count, 3)
        guard case .code(let lang, let code) = blocks[2] else { return XCTFail("expected code block") }
        XCTAssertEqual(lang, "bash")
        XCTAssertEqual(code, "curl -s https://example.com | jq .")
        XCTAssertEqual(blocks[2].copyText, "curl -s https://example.com | jq .")
        XCTAssertFalse(blocks[2].copyText.contains("```"))
    }

    func testUnclosedFenceStillYieldsCode() {
        let blocks = MarkdownBlocks.parse("```\nlet x = 1\nlet y = 2")
        XCTAssertEqual(blocks.first?.copyText, "let x = 1\nlet y = 2")
    }

    func testBareURLIsItsOwnBlock() {
        let blocks = MarkdownBlocks.parse("https://example.com/path?x=1\n\nnot a url line")
        XCTAssertEqual(blocks.first, .url("https://example.com/path?x=1"))
        XCTAssertEqual(blocks.first?.copyText, "https://example.com/path?x=1")
    }

    func testListsAndHeadings() {
        let blocks = MarkdownBlocks.parse("## Todo\n- one\n- two\n\n1. first\n2. second")
        XCTAssertEqual(blocks[0], .heading(level: 2, text: "Todo"))
        XCTAssertEqual(blocks[1], .list(items: ["one", "two"], ordered: false))
        XCTAssertEqual(blocks[2], .list(items: ["first", "second"], ordered: true))
    }

    func testTaskListItems() {
        let blocks = MarkdownBlocks.parse("- [ ] open\n- [x] done")
        XCTAssertEqual(blocks.first, .list(items: ["☐ open", "☑ done"], ordered: false))
    }

    func testIndentationInsideCodeIsPreserved() {
        let blocks = MarkdownBlocks.parse("```swift\nfunc a() {\n    return 1\n}\n```")
        XCTAssertEqual(blocks.first?.copyText, "func a() {\n    return 1\n}")
    }
}
