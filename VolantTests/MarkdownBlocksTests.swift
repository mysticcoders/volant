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
        XCTAssertEqual(blocks[1], .list([MarkdownListItem(text: "one"), MarkdownListItem(text: "two")]))
        XCTAssertEqual(blocks[2], .list([MarkdownListItem(text: "first", number: 1), MarkdownListItem(text: "second", number: 2)]))
    }

    func testTaskListItems() {
        let blocks = MarkdownBlocks.parse("- [ ] open\n- [x] done")
        XCTAssertEqual(blocks.first, .list([MarkdownListItem(text: "☐ open"), MarkdownListItem(text: "☑ done")]))
    }

    func testPipeTablesKeepColumnsAlignmentsAndInlineText() {
        let blocks = MarkdownBlocks.parse("""
        Compared:

        | Option | Cost | Notes |
        |:-------|-----:|:-----:|
        | **Fast** | 12 | uses `a \\| b` |
        | Slow | 3 |
        After the table.
        """)
        XCTAssertEqual(blocks[0], .paragraph("Compared:"))
        XCTAssertEqual(blocks[1], .table(header: ["Option", "Cost", "Notes"], alignments: [.leading, .trailing, .center],
                                         rows: [["**Fast**", "12", "uses `a | b`"], ["Slow", "3", ""]]))
        XCTAssertEqual(blocks[2], .paragraph("After the table."))
        XCTAssertEqual(blocks[1].copyText, "Option\tCost\tNotes\n**Fast**\t12\tuses `a | b`\nSlow\t3\t")
    }

    func testPipesWithoutASeparatorRowStayText() {
        XCTAssertEqual(MarkdownBlocks.parse("a | b\nnext line"), [.paragraph("a | b next line")])
    }

    func testNestedMixedListsKeepDepthAndNumbers() {
        let blocks = MarkdownBlocks.parse("""
        3. Install
           - run `brew install`
           - check the version
        4) Configure

        5. Done
        """)
        XCTAssertEqual(blocks, [.list([
            MarkdownListItem(text: "Install", number: 3),
            MarkdownListItem(text: "run `brew install`", depth: 1),
            MarkdownListItem(text: "check the version", depth: 1),
            MarkdownListItem(text: "Configure", number: 4),
            MarkdownListItem(text: "Done", number: 5)
        ])])
        XCTAssertEqual(blocks[0].copyText, "3. Install\n  • run `brew install`\n  • check the version\n4. Configure\n5. Done")
    }

    func testIndentedLinesContinueTheirItem() {
        let blocks = MarkdownBlocks.parse("- first line\n  wraps here\n- second\n\nAfter")
        XCTAssertEqual(blocks, [.list([MarkdownListItem(text: "first line wraps here"), MarkdownListItem(text: "second")]), .paragraph("After")])
    }

    func testIndentationInsideCodeIsPreserved() {
        let blocks = MarkdownBlocks.parse("```swift\nfunc a() {\n    return 1\n}\n```")
        XCTAssertEqual(blocks.first?.copyText, "func a() {\n    return 1\n}")
    }
}
