import AppKit

/// UTF-16 source ranges match NSTextView exactly, including emoji and CRLF input.
struct CodeFence: Equatable {
    let opening: NSRange
    let languageRange: NSRange
    let content: NSRange
    let closing: NSRange?
    let language: String
    let marker: String

    var extent: NSRange {
        NSRange(location: opening.location, length: (closing.map(NSMaxRange) ?? NSMaxRange(content)) - opening.location)
    }

    func containsCaret(_ location: Int) -> Bool {
        location >= opening.location && (closing == nil ? location <= NSMaxRange(content) : location < NSMaxRange(extent))
    }
}

enum CodeLanguage: String, CaseIterable {
    case auto = "Auto", text = "Plain Text", swift = "Swift", python = "Python"
    case javascript = "JavaScript", typescript = "TypeScript", json = "JSON"
    case shell = "Shell", sql = "SQL", html = "HTML", css = "CSS", markdown = "Markdown"

    var tag: String {
        switch self {
        case .auto: return ""
        case .text: return "text"
        case .shell: return "bash"
        default: return rawValue.lowercased()
        }
    }

    static func from(tag: String) -> CodeLanguage? {
        switch tag.lowercased() {
        case "": return .auto
        case "txt", "plaintext", "text": return .text
        case "js", "jsx", "javascript": return .javascript
        case "ts", "tsx", "typescript": return .typescript
        case "py", "python": return .python
        case "sh", "zsh", "bash", "shell": return .shell
        case "md", "markdown": return .markdown
        default: return allCases.first { $0.tag == tag.lowercased() }
        }
    }

    /// Conservative, local heuristics. Ambiguous/short input stays Plain Text; never executes code.
    static func detect(_ code: String) -> CodeLanguage {
        let sample = String(code.prefix(16_384)).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !sample.isEmpty else { return .text }
        if (sample.hasPrefix("{") || sample.hasPrefix("[")),
           let data = sample.data(using: .utf8), (try? JSONSerialization.jsonObject(with: data)) != nil { return .json }
        func matches(_ pattern: String) -> Bool { sample.range(of: pattern, options: .regularExpression) != nil }
        if matches("(?im)^\\s*(<!doctype html|<html|<div|<body|<p[ >])") { return .html }
        if matches("(?m)^\\s*(import SwiftUI|import Foundation|func \\w+\\(|(?:let|var) \\w+\\s*:\\s*[A-Z]|struct \\w+\\s*[:{])") { return .swift }
        if matches("(?m)^\\s*(def \\w+\\(|class \\w+.*:|from \\w+ import |if __name__|import (?:os|sys|json|re)\\b)") { return .python }
        if matches("(?m)^\\s*(interface \\w+|type \\w+\\s*=|(?:const|let) \\w+\\s*:\\s*(?:string|number|boolean))") { return .typescript }
        if matches("(?m)(console\\.log\\(|const \\w+\\s*=|function \\w+\\(|=>)") { return .javascript }
        if matches("(?im)^\\s*(SELECT\\s+.+\\s+FROM\\b|INSERT INTO\\b|CREATE TABLE\\b|UPDATE\\s+\\w+\\s+SET\\b)") { return .sql }
        if matches("(?m)^\\s*(#!/.*(?:sh|bash)|(?:export \\w+=|echo |curl |sudo |npm |git ))") { return .shell }
        if matches("(?s)[.#]?[\\w-]+\\s*\\{[^}]*[\\w-]+\\s*:\\s*[^;]+;") { return .css }
        if matches("(?m)^#{1,6} ") { return .markdown }
        return .text
    }
}

enum LiveMarkdown {
    static func fences(in text: String) -> [CodeFence] {
        let source = text as NSString
        var result: [CodeFence] = []
        var start: (range: NSRange, language: NSRange, tag: String, marker: String)?
        var position = 0
        while position < source.length {
            let line = source.lineRange(for: NSRange(location: position, length: 0))
            let raw = source.substring(with: line) as NSString
            let trimmed = (raw as String).trimmingCharacters(in: .whitespacesAndNewlines)
            let indent = raw.length - (raw as String).drop(while: { $0 == " " || $0 == "\t" }).utf16.count
            if let open = start {
                if indent <= 3, !raw.substring(to: indent).contains("\t"), trimmed.allSatisfy({ String($0) == String(open.marker.prefix(1)) }), trimmed.count >= open.marker.count {
                    result.append(CodeFence(opening: open.range, languageRange: open.language,
                                            content: NSRange(location: NSMaxRange(open.range), length: line.location - NSMaxRange(open.range)),
                                            closing: line, language: open.tag, marker: open.marker))
                    start = nil
                }
            } else if indent <= 3, !raw.substring(to: indent).contains("\t"), let first = trimmed.first, first == "`" || first == "~" {
                let marker = String(trimmed.prefix(while: { $0 == first }))
                let info = String(trimmed.dropFirst(marker.count))
                if marker.count >= 3, !(first == "`" && info.contains("`")) {
                    let tag = info.trimmingCharacters(in: .whitespaces)
                    let end = (raw as String).trimmingCharacters(in: .newlines).utf16.count
                    let location = line.location + indent + marker.utf16.count
                    start = (line, NSRange(location: location, length: max(0, end - indent - marker.utf16.count)), tag, marker)
                }
            }
            position = NSMaxRange(line)
        }
        if let open = start {
            result.append(CodeFence(opening: open.range, languageRange: open.language,
                                    content: NSRange(location: NSMaxRange(open.range), length: source.length - NSMaxRange(open.range)),
                                    closing: nil, language: open.tag, marker: open.marker))
        }
        return result
    }

    static func activeFence(in text: String, selection: NSRange) -> CodeFence? {
        fences(in: text).first { $0.containsCaret(selection.location) }
    }

    static func language(for fence: CodeFence, in text: String) -> CodeLanguage {
        if !fence.language.isEmpty { return CodeLanguage.from(tag: fence.language) ?? .text }
        return CodeLanguage.detect((text as NSString).substring(with: fence.content))
    }

    static let bodyFont = NSFont.systemFont(ofSize: 15)
    static let codeFont = NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)
    static var bodyAttributes: [NSAttributedString.Key: Any] {
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = 4
        return [.font: bodyFont, .foregroundColor: NSColor.labelColor, .paragraphStyle: paragraph]
    }

    /// Presentation attributes only: styling never rewrites source or changes source offsets.
    static func styled(_ text: String, live: Bool) -> NSAttributedString {
        let source = text as NSString
        let output = NSMutableAttributedString(string: text, attributes: bodyAttributes)
        let all = NSRange(location: 0, length: source.length)
        guard live else {
            output.addAttribute(.font, value: codeFont, range: all)
            return output
        }
        let blocks = fences(in: text)
        func outsideCode(_ range: NSRange) -> Bool { !blocks.contains { NSIntersectionRange($0.extent, range).length > 0 } }
        func style(_ pattern: String, attributes: [NSAttributedString.Key: Any]) {
            guard let regex = try? NSRegularExpression(pattern: pattern, options: [.anchorsMatchLines]) else { return }
            for match in regex.matches(in: text, range: all) where outsideCode(match.range) {
                output.addAttributes(attributes, range: match.range)
            }
        }
        style("^#{1,2} .+$", attributes: [.font: NSFont.systemFont(ofSize: 22, weight: .semibold)])
        style("^#{3,6} .+$", attributes: [.font: NSFont.systemFont(ofSize: 17, weight: .semibold)])
        style("\\*\\*[^*\\n]+\\*\\*", attributes: [.font: NSFont.boldSystemFont(ofSize: 15)])
        style("(?<!\\*)\\*[^*\\n]+\\*(?!\\*)", attributes: [.font: NSFontManager.shared.convert(bodyFont, toHaveTrait: .italicFontMask)])
        style("`[^`\\n]+`", attributes: [.font: codeFont, .backgroundColor: NSColor.quaternaryLabelColor.withAlphaComponent(0.12)])
        style("^>.*$", attributes: [.foregroundColor: NSColor.secondaryLabelColor])
        for block in blocks {
            output.addAttributes([.font: codeFont, .backgroundColor: NSColor.quaternaryLabelColor.withAlphaComponent(0.12)], range: block.extent)
            let fenceAttributes: [NSAttributedString.Key: Any] = [.font: NSFont.monospacedSystemFont(ofSize: 11, weight: .medium), .foregroundColor: NSColor.secondaryLabelColor]
            output.addAttributes(fenceAttributes, range: block.opening)
            if let closing = block.closing { output.addAttributes(fenceAttributes, range: closing) }
            let language = language(for: block, in: text)
            guard language != .text else { continue }
            // Lightweight token coloring, deliberately not a compiler or a language server.
            let patterns: [(String, NSColor)] = [
                (#"\b(?:let|var|func|struct|class|import|return|if|else|for|while|const|function|def|from|async|await|true|false|null|nil|SELECT|FROM|WHERE|interface|type)\b"#, .systemPurple),
                (#"\b\d+(?:\.\d+)?\b"#, .systemBrown),
                (#""(?:[^"\\]|\\.)*"|'(?:[^'\\]|\\.)*'"#, NSColor.systemGreen.blended(withFraction: 0.3, of: .labelColor) ?? .labelColor)
            ]
            for (pattern, color) in patterns {
                guard let regex = try? NSRegularExpression(pattern: pattern) else { continue }
                for match in regex.matches(in: text, range: block.content) {
                    output.addAttribute(.foregroundColor, value: color, range: match.range)
                }
            }
        }
        return output
    }
}
