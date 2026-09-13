import AppKit
import SwiftUI
import XCTest
@testable import Volant

final class LiveMarkdownTests: XCTestCase {
    func testFenceStartsImmediatelyAndEndsAtMatchingMarker() throws {
        let opening = try XCTUnwrap(LiveMarkdown.fences(in: "Thought\n```").first)
        XCTAssertNil(opening.closing)
        XCTAssertEqual(opening.content.length, 0)
        XCTAssertTrue(opening.containsCaret("Thought\n```".utf16.count))
        let text = "````python\nprint('hello')\n```\nstill code\n````\nProse"
        let block = try XCTUnwrap(LiveMarkdown.fences(in: text).first)
        XCTAssertEqual((text as NSString).substring(with: block.content), "print('hello')\n```\nstill code\n")
        XCTAssertNotNil(block.closing)
        XCTAssertEqual(MarkdownBlocks.parse(text).first, .code(language: "python", code: "print('hello')\n```\nstill code"))
        XCTAssertNil(LiveMarkdown.activeFence(in: text, selection: NSRange(location: text.utf16.count, length: 0)))
    }

    func testUTF16CRLFAndMultipleBlocks() throws {
        let text = "📝 café\r\n  ```js\r\nconsole.log('你好');\r\n  ```\r\n\r\n~~~sql\r\nSELECT * FROM notes;\r\n~~~"
        let blocks = LiveMarkdown.fences(in: text)
        XCTAssertEqual(blocks.count, 2)
        XCTAssertEqual((text as NSString).substring(with: blocks[0].languageRange), "js")
        XCTAssertEqual((text as NSString).substring(with: blocks[0].content), "console.log('你好');\r\n")
        XCTAssertEqual(LiveMarkdown.language(for: blocks[1], in: text), .sql)
        XCTAssertTrue(LiveMarkdown.fences(in: "inline ``` is not a block").isEmpty)
        XCTAssertTrue(LiveMarkdown.fences(in: "    ```\nindented").isEmpty)
    }

    func testDetectionIsConservativeAndExplicitTagsWin() throws {
        let cases: [(String, CodeLanguage)] = [
            ("", .text), ("hello world", .text), ("let answer = 42", .text), ("print(value)", .text),
            ("{\"name\":\"Mina\",\"count\":2}", .json),
            ("def greet(name):\n    return name", .python),
            ("import SwiftUI\nstruct Note: View {}", .swift),
            ("const greeting = 'hello';\nconsole.log(greeting)", .javascript),
            ("interface Note { title: string }", .typescript),
            ("SELECT title FROM notes;", .sql), ("#!/bin/bash\necho hello", .shell)
        ]
        for (source, expected) in cases { XCTAssertEqual(CodeLanguage.detect(source), expected, source) }
        let text = "```text\nSELECT title FROM notes;\n```"
        let block = try XCTUnwrap(LiveMarkdown.fences(in: text).first)
        XCTAssertEqual(LiveMarkdown.language(for: block, in: text), .text)
        XCTAssertEqual(CodeLanguage.from(tag: "PY"), .python)
        XCTAssertNil(CodeLanguage.from(tag: "rust"))
    }

    func testStylingPreservesExactSourceAndDoesNotStyleHeadingsInsideCode() throws {
        let text = "# Heading\n📝 **bold**\n```python\n# comment\nreturn 'café'\n```\n"
        let styled = LiveMarkdown.styled(text, live: true)
        XCTAssertEqual(styled.string, text)
        XCTAssertEqual(styled.length, text.utf16.count)
        let headingFont = try XCTUnwrap(styled.attribute(.font, at: 0, effectiveRange: nil) as? NSFont)
        let comment = (text as NSString).range(of: "# comment")
        let codeFont = try XCTUnwrap(styled.attribute(.font, at: comment.location, effectiveRange: nil) as? NSFont)
        XCTAssertGreaterThan(headingFont.pointSize, codeFont.pointSize)
        XCTAssertEqual(LiveMarkdown.styled(text, live: false).string, text)
    }

    @MainActor
    func testLanguageChangePreservesContentSelectionAndUndo() throws {
        var text = "📝\n```\nconsole.log('hello');\n```\n"
        let original = text
        let state = LiveEditorState()
        let root = LiveMarkdownEditor(text: Binding(get: { text }, set: { text = $0 }), live: true, state: state)
        let host = NSHostingView(rootView: root)
        host.frame = NSRect(x: 0, y: 0, width: 500, height: 300)
        host.layoutSubtreeIfNeeded()
        let view = try XCTUnwrap(state.textView)
        let selection = (text as NSString).range(of: "hello")
        view.setSelectedRange(selection)
        state.chooseLanguage(.javascript)
        XCTAssertTrue(view.string.contains("```javascript\n"))
        XCTAssertEqual((view.string as NSString).substring(with: view.selectedRange()), "hello")
        XCTAssertTrue(view.undoManager?.canUndo ?? false)
        view.undoManager?.undo()
        XCTAssertEqual(view.string, original)
        view.undoManager?.redo()
        XCTAssertTrue(view.string.contains("```javascript\n"))
        state.chooseLanguage(.auto)
        XCTAssertEqual(view.string, original)
        withExtendedLifetime(host) {}
    }

    @MainActor
    func testTypingFenceAndChangingModesDoNotRewriteSource() throws {
        var text = ""
        let state = LiveEditorState()
        let host = NSHostingView(rootView: LiveMarkdownEditor(text: Binding(get: { text }, set: { text = $0 }), live: true, state: state))
        host.frame = NSRect(x: 0, y: 0, width: 500, height: 300)
        host.layoutSubtreeIfNeeded()
        let view = try XCTUnwrap(state.textView)
        view.insertText("```", replacementRange: NSRange(location: 0, length: 0))
        XCTAssertEqual(text, "```")
        XCTAssertNotNil(LiveMarkdown.activeFence(in: text, selection: view.selectedRange()))
        view.insertText("\ndef greet():\n    return 'hello'\n```\nprose", replacementRange: view.selectedRange())
        XCTAssertEqual(LiveMarkdown.fences(in: text).count, 1)
        let original = text, selected = view.selectedRange()
        let coordinator = LiveMarkdownEditor.Coordinator(parent: LiveMarkdownEditor(text: Binding(get: { text }, set: { text = $0 }), live: false, state: state))
        coordinator.style(view)
        XCTAssertEqual(view.string, original)
        XCTAssertEqual(view.selectedRange(), selected)
        XCTAssertNil(LiveMarkdown.activeFence(in: text, selection: selected))
        withExtendedLifetime(host) {}
    }
}
