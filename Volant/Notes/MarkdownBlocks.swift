import Foundation

/// A minimal block-level Markdown model. The point is copy semantics: a code block knows its contents
/// without fences, and a bare URL line knows the URL. Inline styling is left to AttributedString.
enum MarkdownBlock: Equatable {
    case heading(level: Int, text: String)
    case paragraph(String)
    case code(language: String?, code: String)
    case list(items: [String], ordered: Bool)
    case quote(String)
    case url(String)
    case rule

    /// What a copy action yields for this block: code without fences, a URL as-is, otherwise the text.
    var copyText: String {
        switch self {
        case .code(_, let code): return code
        case .url(let u): return u
        case .heading(_, let t), .paragraph(let t), .quote(let t): return t
        case .list(let items, let ordered):
            return items.enumerated().map { ordered ? "\($0.offset + 1). \($0.element)" : "• \($0.element)" }.joined(separator: "\n")
        case .rule: return ""
        }
    }
}

/// A block with a stable identity: its position in the document.
struct IndexedBlock: Identifiable {
    let id: Int
    let block: MarkdownBlock
}

enum MarkdownBlocks {
    static func parseIndexed(_ text: String) -> [IndexedBlock] {
        parse(text).enumerated().map { IndexedBlock(id: $0.offset, block: $0.element) }
    }

    static func parse(_ text: String) -> [MarkdownBlock] {
        var blocks: [MarkdownBlock] = []
        var paragraph: [String] = []
        var listItems: [String] = []
        var listOrdered = false
        var code: [String]? = nil
        var codeLang: String? = nil
        var currentFence: CodeFence?
        let source = text as NSString
        let fences = Dictionary(uniqueKeysWithValues: LiveMarkdown.fences(in: text).map { ($0.opening.location, $0) })
        var position = 0

        func flushParagraph() {
            guard !paragraph.isEmpty else { return }
            let joined = paragraph.joined(separator: " ")
            blocks.append(isBareURL(joined) ? .url(joined) : .paragraph(joined))
            paragraph = []
        }
        func flushList() {
            guard !listItems.isEmpty else { return }
            blocks.append(.list(items: listItems, ordered: listOrdered))
            listItems = []
        }

        while position < source.length {
            let range = source.lineRange(for: NSRange(location: position, length: 0))
            let lineStart = position
            position = NSMaxRange(range)
            let raw = source.substring(with: range).trimmingCharacters(in: .newlines)
            let line = raw.trimmingCharacters(in: .whitespaces)
            if let current = code {
                if currentFence?.closing?.location == lineStart {
                    blocks.append(.code(language: codeLang, code: current.joined(separator: "\n")))
                    code = nil; codeLang = nil; currentFence = nil
                } else {
                    code!.append(raw)
                }
                continue
            }
            if let fence = fences[lineStart] {
                flushParagraph(); flushList()
                code = []
                currentFence = fence
                codeLang = fence.language.isEmpty ? nil : fence.language
                continue
            }
            if line.isEmpty { flushParagraph(); flushList(); continue }
            if line == "---" || line == "***" { flushParagraph(); flushList(); blocks.append(.rule); continue }
            if let level = headingLevel(line) {
                flushParagraph(); flushList()
                blocks.append(.heading(level: level, text: String(line.drop(while: { $0 == "#" })).trimmingCharacters(in: .whitespaces)))
                continue
            }
            if line.hasPrefix("> ") || line == ">" {
                flushParagraph(); flushList()
                blocks.append(.quote(String(line.dropFirst(1)).trimmingCharacters(in: .whitespaces)))
                continue
            }
            if let item = unorderedItem(line) {
                flushParagraph()
                if !listItems.isEmpty && listOrdered { flushList() }
                listOrdered = false; listItems.append(item); continue
            }
            if let item = orderedItem(line) {
                flushParagraph()
                if !listItems.isEmpty && !listOrdered { flushList() }
                listOrdered = true; listItems.append(item); continue
            }
            flushList()
            paragraph.append(line)
        }
        if let current = code { blocks.append(.code(language: codeLang, code: current.joined(separator: "\n"))) }
        flushParagraph(); flushList()
        return blocks
    }

    private static func headingLevel(_ line: String) -> Int? {
        let hashes = line.prefix { $0 == "#" }.count
        guard hashes >= 1, hashes <= 6, line.dropFirst(hashes).first == " " else { return nil }
        return hashes
    }

    private static func unorderedItem(_ line: String) -> String? {
        for marker in ["- [ ] ", "* [ ] "] where line.hasPrefix(marker) { return "☐ " + String(line.dropFirst(marker.count)) }
        for marker in ["- [x] ", "- [X] ", "* [x] "] where line.hasPrefix(marker) { return "☑ " + String(line.dropFirst(marker.count)) }
        for marker in ["- ", "* ", "+ "] where line.hasPrefix(marker) { return String(line.dropFirst(2)) }
        return nil
    }

    private static func orderedItem(_ line: String) -> String? {
        let digits = line.prefix { $0.isNumber }
        guard !digits.isEmpty, line.dropFirst(digits.count).hasPrefix(". ") else { return nil }
        return String(line.dropFirst(digits.count + 2))
    }

    static func isBareURL(_ text: String) -> Bool {
        guard !text.contains(" "), let url = URL(string: text), let scheme = url.scheme?.lowercased() else { return false }
        return ["http", "https", "mailto", "ssh", "git"].contains(scheme)
    }
}
