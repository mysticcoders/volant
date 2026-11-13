import SwiftUI
import UIKit

/// One rendered unit of a note: a heading, paragraph, list item, quote, rule or fenced code.
enum MarkdownBlock: Hashable {
    case heading(level: Int, text: String)
    case paragraph(String)
    case bullet(marker: String, text: String, indent: Int)
    case quote(String)
    case code(language: String, text: String)
    case rule

    /// Splits Markdown into blocks. Fences follow the Mac editor's rules: backtick or tilde runs of
    /// three or more, closed by the same character at the same or greater length; an unclosed
    /// fence runs to the end of the note.
    static func parse(_ source: String) -> [MarkdownBlock] {
        var blocks: [MarkdownBlock] = []
        var paragraph: [String] = []
        var fence: (char: Character, length: Int, language: String, lines: [String])?

        func flushParagraph() {
            guard !paragraph.isEmpty else { return }
            blocks.append(.paragraph(paragraph.joined(separator: "\n")))
            paragraph.removeAll()
        }

        for raw in source.components(separatedBy: .newlines) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if var open = fence {
                if let close = fenceMarker(line), close.char == open.char, close.length >= open.length, close.info.isEmpty {
                    blocks.append(.code(language: open.language, text: open.lines.joined(separator: "\n")))
                    fence = nil
                } else {
                    open.lines.append(raw)
                    fence = open
                }
                continue
            }
            if let marker = fenceMarker(line) {
                flushParagraph()
                fence = (marker.char, marker.length, marker.info, [])
                continue
            }
            if line.isEmpty { flushParagraph(); continue }
            if let heading = headingLevel(line) {
                flushParagraph()
                blocks.append(.heading(level: heading.level, text: heading.text))
            } else if ["---", "***", "___"].contains(line.replacingOccurrences(of: " ", with: "")) {
                flushParagraph()
                blocks.append(.rule)
            } else if line.hasPrefix(">") {
                flushParagraph()
                blocks.append(.quote(String(line.dropFirst()).trimmingCharacters(in: .whitespaces)))
            } else if let item = listItem(raw) {
                flushParagraph()
                blocks.append(item)
            } else {
                paragraph.append(line)
            }
        }
        if let open = fence { blocks.append(.code(language: open.language, text: open.lines.joined(separator: "\n"))) }
        flushParagraph()
        return blocks
    }

    /// A fence opener or closer: its character, run length and info string.
    private static func fenceMarker(_ line: String) -> (char: Character, length: Int, info: String)? {
        guard let first = line.first, first == "`" || first == "~" else { return nil }
        let run = line.prefix { $0 == first }.count
        guard run >= 3 else { return nil }
        let info = line.dropFirst(run).trimmingCharacters(in: .whitespaces)
        if first == "`" && info.contains("`") { return nil }
        return (first, run, info)
    }

    private static func headingLevel(_ line: String) -> (level: Int, text: String)? {
        let hashes = line.prefix { $0 == "#" }.count
        guard (1...6).contains(hashes), line.dropFirst(hashes).first == " " else { return nil }
        return (hashes, line.dropFirst(hashes + 1).trimmingCharacters(in: .whitespaces))
    }

    private static func listItem(_ raw: String) -> MarkdownBlock? {
        let indent = raw.prefix { $0 == " " || $0 == "\t" }.count / 2
        let line = raw.trimmingCharacters(in: .whitespaces)
        for prefix in ["- [ ] ", "- [x] ", "- [X] "] where line.hasPrefix(prefix) {
            return .bullet(marker: prefix.contains("[ ]") ? "\u{25A2}" : "\u{2611}", text: String(line.dropFirst(prefix.count)), indent: indent)
        }
        for prefix in ["- ", "* ", "+ "] where line.hasPrefix(prefix) {
            return .bullet(marker: "\u{2022}", text: String(line.dropFirst(2)), indent: indent)
        }
        let digits = line.prefix { $0.isNumber }
        if !digits.isEmpty, line.dropFirst(digits.count).hasPrefix(". ") {
            return .bullet(marker: "\(digits).", text: String(line.dropFirst(digits.count + 2)), indent: indent)
        }
        return nil
    }
}

/// Read-only rendering of a note without Markdown markers, the iOS counterpart of the Mac Preview mode.
struct MarkdownPreview: View {
    let source: String
    @Environment(\.volantTheme) private var theme

    var body: some View {
        let blocks = MarkdownBlock.parse(source)
        VStack(alignment: .leading, spacing: 12) {
            ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                view(for: block)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .textSelection(.enabled)
    }

    @ViewBuilder
    private func view(for block: MarkdownBlock) -> some View {
        switch block {
        case let .heading(level, text):
            Text(inline(text)).font(headingFont(level)).padding(.top, level <= 2 ? 6 : 2)
        case let .paragraph(text):
            Text(inline(text)).font(.body)
        case let .bullet(marker, text, indent):
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(marker).foregroundStyle(.secondary).monospacedDigit()
                Text(inline(text))
            }
            .padding(.leading, CGFloat(indent) * 18)
        case let .quote(text):
            Text(inline(text))
                .foregroundStyle(.secondary)
                .padding(.leading, 12)
                .overlay(alignment: .leading) { Capsule().fill(.tint).frame(width: 3) }
        case let .code(language, text):
            CodeBlockView(language: language, code: text)
        case .rule:
            Divider()
        }
    }

    private func headingFont(_ level: Int) -> Font {
        switch level {
        case 1: .title.weight(.bold)
        case 2: .title2.weight(.semibold)
        case 3: .title3.weight(.semibold)
        default: .headline
        }
    }

    /// Inline emphasis, code and links through Foundation's Markdown parser, falling back on the raw text.
    private func inline(_ text: String) -> AttributedString {
        let options = AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        return (try? AttributedString(markdown: text, options: options)) ?? AttributedString(text)
    }
}

/// A fenced code block with its language label and a Copy button, like the Mac code-block bar.
struct CodeBlockView: View {
    let language: String
    let code: String
    @Environment(\.volantTheme) private var theme
    @State private var copied = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Label(language.isEmpty ? String(localized: "Code") : language, systemImage: "chevron.left.forwardslash.chevron.right")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                Spacer()
                Button {
                    UIPasteboard.general.string = code
                    copied = true
                    Task { try? await Task.sleep(for: .seconds(1.5)); copied = false }
                } label: {
                    Label(copied ? "Copied" : "Copy Code", systemImage: copied ? "checkmark" : "doc.on.doc")
                        .font(.caption.weight(.medium))
                }
                .buttonStyle(.borderless)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            Divider()
            ScrollView(.horizontal, showsIndicators: false) {
                Text(code)
                    .font(.system(.callout, design: .monospaced))
                    .padding(12)
            }
        }
        .background(theme.raisedSurface, in: RoundedRectangle(cornerRadius: NotesStyle.radius, style: .continuous))
    }
}
