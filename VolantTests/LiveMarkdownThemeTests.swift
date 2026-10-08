import AppKit
import SwiftUI
import VolantCore
import XCTest
@testable import Volant

final class LiveMarkdownThemeTests: XCTestCase {
    private let sample = "# Plan\n\n> quoted\n\nUse `ready` here.\n\n```swift\nlet count = 3\nlet name = \"Ada\"\n```\n"

    /// Without a palette the styling keeps the semantic system colors it always used.
    func testSystemStylingKeepsSemanticColors() throws {
        let styled = LiveMarkdown.styled(sample, live: true)
        XCTAssertEqual(styled.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? NSColor, .labelColor)
        let quote = (sample as NSString).range(of: "> quoted")
        XCTAssertEqual(styled.attribute(.foregroundColor, at: quote.location, effectiveRange: nil) as? NSColor, .secondaryLabelColor)
        let keyword = (sample as NSString).range(of: "let count")
        XCTAssertEqual(styled.attribute(.foregroundColor, at: keyword.location, effectiveRange: nil) as? NSColor, .systemPurple)
    }

    /// A palette theme colors prose, dimmed syntax, code backgrounds and tokens from its editor colors.
    func testPaletteStylingUsesEditorColors() throws {
        let theme = ResolvedTheme(ColorTheme.named("catppuccin-mocha"))
        let editor = EditorColors(palette: try XCTUnwrap(theme.palette))
        let styled = LiveMarkdown.styled(sample, live: true, colors: EditorPalette(theme))
        let source = sample as NSString
        func hex(_ key: NSAttributedString.Key, at text: String) throws -> String {
            let color = try XCTUnwrap(styled.attribute(key, at: source.range(of: text).location, effectiveRange: nil) as? NSColor)
            let srgb = try XCTUnwrap(color.usingColorSpace(.sRGB))
            return String(format: "#%02x%02x%02x", Int((srgb.redComponent * 255).rounded()), Int((srgb.greenComponent * 255).rounded()),
                          Int((srgb.blueComponent * 255).rounded()))
        }
        XCTAssertEqual(try hex(.foregroundColor, at: "Plan"), editor.text)
        XCTAssertEqual(try hex(.foregroundColor, at: "> quoted"), editor.syntax)
        XCTAssertEqual(try hex(.backgroundColor, at: "`ready`"), editor.code)
        XCTAssertEqual(try hex(.foregroundColor, at: "```swift"), editor.syntax)
        XCTAssertEqual(try hex(.foregroundColor, at: "let count"), editor.keyword)
        XCTAssertEqual(try hex(.foregroundColor, at: "3\n"), editor.number)
        XCTAssertEqual(try hex(.foregroundColor, at: "\"Ada\""), editor.string)
        XCTAssertEqual(styled.string, sample)
    }

    /// Switching themes recolors the editor without touching its source, selection or undo history,
    /// and switching back restores the text view's own caret and selection colors.
    @MainActor
    func testThemeChangeRestylesWithoutEditing() throws {
        var text = sample
        let (view, coordinator) = editor(binding: Binding(get: { text }, set: { text = $0 }))
        coordinator.adopt(.system, in: view, restyle: true)
        let systemCaret = view.insertionPointColor
        let systemSelection = view.selectedTextAttributes[.backgroundColor] as? NSColor
        view.setSelectedRange(NSRange(location: 2, length: 0))
        view.insertText("x", replacementRange: view.selectedRange())
        let edited = view.string, selection = view.selectedRange()
        XCTAssertTrue(view.undoManager?.canUndo ?? false)

        let mocha = ResolvedTheme(ColorTheme.named("catppuccin-mocha"))
        let palette = EditorPalette(mocha)
        coordinator.adopt(mocha, in: view, restyle: true)
        XCTAssertEqual(view.string, edited)
        XCTAssertEqual(view.selectedRange(), selection)
        XCTAssertEqual(view.textStorage?.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? NSColor, palette.text)
        XCTAssertEqual(view.insertionPointColor, palette.caret)
        XCTAssertEqual(view.selectedTextAttributes[.backgroundColor] as? NSColor, palette.selection)
        XCTAssertEqual(view.typingAttributes[.foregroundColor] as? NSColor, palette.text)
        view.undoManager?.undo()
        XCTAssertEqual(view.string, sample, "undo reverts the typed character, not the restyle")

        coordinator.adopt(.system, in: view, restyle: true)
        XCTAssertEqual(view.textStorage?.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? NSColor, .labelColor)
        XCTAssertEqual(view.insertionPointColor, systemCaret)
        XCTAssertEqual(view.selectedTextAttributes[.backgroundColor] as? NSColor, systemSelection)
    }

    /// A theme change while an input method is composing leaves the marked text alone; the new
    /// colors apply once the composition is committed.
    @MainActor
    func testThemeChangeWaitsForComposition() throws {
        var text = "Note "
        let (view, coordinator) = editor(binding: Binding(get: { text }, set: { text = $0 }))
        coordinator.adopt(.system, in: view, restyle: true)
        view.setSelectedRange(NSRange(location: 5, length: 0))
        view.setMarkedText("にほ", selectedRange: NSRange(location: 2, length: 0), replacementRange: NSRange(location: NSNotFound, length: 0))
        XCTAssertTrue(view.hasMarkedText())
        let mocha = ResolvedTheme(ColorTheme.named("catppuccin-mocha"))
        coordinator.adopt(mocha, in: view, restyle: true)
        XCTAssertTrue(view.hasMarkedText())
        XCTAssertEqual(view.string, "Note にほ")
        view.insertText("日本", replacementRange: view.markedRange())
        XCTAssertFalse(view.hasMarkedText())
        coordinator.style(view)
        XCTAssertEqual(view.string, "Note 日本")
        XCTAssertEqual(view.textStorage?.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? NSColor, EditorPalette(mocha).text)
    }

    /// A live editor's text view and coordinator, wired the way the representable wires them.
    @MainActor
    private func editor(binding: Binding<String>) -> (MarkdownTextView, LiveMarkdownEditor.Coordinator) {
        let view = MarkdownTextView(frame: NSRect(x: 0, y: 0, width: 400, height: 300))
        view.isRichText = false
        view.allowsUndo = true
        view.string = binding.wrappedValue
        let coordinator = LiveMarkdownEditor.Coordinator(parent: LiveMarkdownEditor(text: binding, live: true, state: LiveEditorState()))
        view.delegate = coordinator
        return (view, coordinator)
    }
}
