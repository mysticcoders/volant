import Foundation

/// One list item: its text, how deeply it is nested, and its number in an ordered list (nil for a bullet).
struct MarkdownListItem: Equatable {
    let text: String
    var depth = 0
    var number: Int?
}

/// How a table column's cells line up, from the colons in the table's separator row.
enum MarkdownColumnAlignment: Equatable {
    case leading, center, trailing
}

/// A minimal block-level Markdown model. The point is copy semantics: a code block knows its contents
/// without fences, and a bare URL line knows the URL. Inline styling is left to AttributedString.
enum MarkdownBlock: Equatable {
    case heading(level: Int, text: String)
    case paragraph(String)
    case code(language: String?, code: String)
    case list([MarkdownListItem])
    case table(header: [String], alignments: [MarkdownColumnAlignment], rows: [[String]])
    case quote(String)
    case url(String)
    case rule

    /// What a copy action yields for this block: code without fences, a URL as-is, otherwise the text.
    var copyText: String {
        switch self {
        case .code(_, let code): return code
        case .url(let u): return u
        case .heading(_, let t), .paragraph(let t), .quote(let t): return t
        case .list(let items):
            return items.map { String(repeating: "  ", count: $0.depth) + ($0.number.map { "\($0). " } ?? "• ") + $0.text }.joined(separator: "\n")
        case .table(let header, _, let rows):
            return ([header] + rows).map { $0.joined(separator: "\t") }.joined(separator: "\n")
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
        var listItems: [MarkdownListItem] = []
        var listIndents: [Int] = []
        var listGap = false
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
            blocks.append(.list(listItems))
            listItems = []; listIndents = []; listGap = false
        }
        /// Adds an item, nesting it under the previous one when it is indented further. Switching between
        /// bullets and numbers at the top level starts a new list, as in Markdown.
        func addItem(_ text: String, number: Int?, indent: Int) {
            var indents = listIndents
            while let last = indents.last, indent < last { indents.removeLast() }
            if indents.last != indent { indents.append(indent) }
            if indents.count == 1, let top = listItems.last(where: { $0.depth == 0 }), (top.number == nil) != (number == nil) {
                flushList(); indents = [indent]
            }
            listIndents = indents
            listItems.append(MarkdownListItem(text: text, depth: listIndents.count - 1, number: number))
            listGap = false
        }
        /// The line after `end`, without its newline, or nil at the end of the text.
        func nextLine(after end: Int) -> String? {
            guard end < source.length else { return nil }
            return source.substring(with: source.lineRange(for: NSRange(location: end, length: 0))).trimmingCharacters(in: .newlines)
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
            // A blank line ends a paragraph, but a list continues if another item follows it.
            if line.isEmpty { flushParagraph(); if !listItems.isEmpty { listGap = true }; continue }
            let indent = indentation(raw)
            if line == "---" || line == "***" || line == "___" { flushParagraph(); flushList(); blocks.append(.rule); continue }
            if line.contains("|"), let next = nextLine(after: position), let alignments = tableAlignments(next) {
                let header = tableCells(line)
                if header.count == alignments.count {
                    flushParagraph(); flushList()
                    position = NSMaxRange(source.lineRange(for: NSRange(location: position, length: 0)))
                    var rows: [[String]] = []
                    while let row = nextLine(after: position), row.contains("|"), !row.trimmingCharacters(in: .whitespaces).isEmpty {
                        position = NSMaxRange(source.lineRange(for: NSRange(location: position, length: 0)))
                        let cells = tableCells(row)
                        rows.append(Array((cells + Array(repeating: "", count: max(0, header.count - cells.count))).prefix(header.count)))
                    }
                    blocks.append(.table(header: header, alignments: alignments, rows: rows))
                    continue
                }
            }
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
                flushParagraph(); addItem(item, number: nil, indent: indent); continue
            }
            if let ordered = orderedItem(line) {
                flushParagraph(); addItem(ordered.text, number: ordered.number, indent: indent); continue
            }
            // An indented line under an item continues that item's text.
            if !listItems.isEmpty, indent > 0, let last = listItems.popLast() {
                listItems.append(MarkdownListItem(text: last.text + (listGap ? "\n" : " ") + line, depth: last.depth, number: last.number))
                listGap = false
                continue
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

    /// An ordered item's number and text, for both `3. text` and `3) text`.
    private static func orderedItem(_ line: String) -> (number: Int, text: String)? {
        let digits = line.prefix { $0.isNumber }
        let rest = line.dropFirst(digits.count)
        guard !digits.isEmpty, digits.count <= 9, rest.hasPrefix(". ") || rest.hasPrefix(") "), let number = Int(digits) else { return nil }
        return (number, String(rest.dropFirst(2)))
    }

    /// Leading whitespace in columns, counting a tab as four.
    private static func indentation(_ raw: String) -> Int {
        raw.prefix { $0 == " " || $0 == "\t" }.reduce(0) { $0 + ($1 == "\t" ? 4 : 1) }
    }

    /// A table row's cells: split on unescaped pipes, with the optional outer pipes removed.
    static func tableCells(_ line: String) -> [String] {
        var cells: [String] = [], current = "", escaped = false
        for character in line.trimmingCharacters(in: .whitespaces) {
            if escaped { current.append(character); escaped = false }
            else if character == "\\" { escaped = true }
            else if character == "|" { cells.append(current); current = "" }
            else { current.append(character) }
        }
        cells.append(current)
        if cells.first?.trimmingCharacters(in: .whitespaces).isEmpty == true { cells.removeFirst() }
        if cells.last?.trimmingCharacters(in: .whitespaces).isEmpty == true { cells.removeLast() }
        return cells.map { $0.trimmingCharacters(in: .whitespaces) }
    }

    /// The column alignments when `line` is a table's separator row, such as `|:---|---:|`, otherwise nil.
    private static func tableAlignments(_ line: String) -> [MarkdownColumnAlignment]? {
        guard line.contains("-") else { return nil }
        let cells = tableCells(line)
        guard !cells.isEmpty else { return nil }
        var alignments: [MarkdownColumnAlignment] = []
        for cell in cells {
            let dashes = cell.trimmingCharacters(in: CharacterSet(charactersIn: ":"))
            guard !dashes.isEmpty, dashes.allSatisfy({ $0 == "-" }) else { return nil }
            alignments.append(cell.hasPrefix(":") && cell.hasSuffix(":") ? .center : cell.hasSuffix(":") ? .trailing : .leading)
        }
        return alignments
    }

    static func isBareURL(_ text: String) -> Bool {
        guard !text.contains(" "), let url = URL(string: text), let scheme = url.scheme?.lowercased() else { return false }
        return ["http", "https", "mailto", "ssh", "git"].contains(scheme)
    }
}
