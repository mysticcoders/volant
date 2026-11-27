import Foundation

/// How a finished dictation is laid out before it is typed, chosen on the Volant keyboard. Every
/// style only rearranges what was said: sentences are regrouped and punctuation at their edges is
/// adjusted, but no word is added, removed or reworded. Greetings and sign-offs are recognized in
/// English only; other languages get the sentence layout alone.
public enum DictationStyle: String, CaseIterable, Codable, Sendable, Identifiable {
    /// Exactly as transcribed.
    case plain
    /// A chat message: one block, without a closing period.
    case message
    /// An email: the greeting and the sign-off on their own lines, the body in short paragraphs.
    case email
    /// A list: one bullet per sentence.
    case notes

    public var id: String { rawValue }

    /// Body paragraphs of an email hold at most this many sentences.
    public static let sentencesPerParagraph = 3

    /// The transcript laid out in this style. Text that already has line breaks, from spoken
    /// lists or "new line" (`DictationFormatting`), keeps its lines: Notes and Email leave it as it
    /// is, and Message drops only the last line's closing period.
    public func format(_ text: String, locale: Locale = .current) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }
        if trimmed.contains("\n") {
            return self == .message ? Self.droppingClosingPeriod(trimmed) : trimmed
        }
        switch self {
        case .plain:
            return trimmed
        case .message:
            return Self.droppingClosingPeriod(trimmed)
        case .notes:
            return Self.sentences(in: trimmed).map { "- " + Self.droppingClosingPeriod($0) }.joined(separator: "\n")
        case .email:
            return Self.email(trimmed, english: locale.language.languageCode?.identifier == "en")
        }
    }

    /// The text split after each sentence end (".", "!", "?" or "…", with any closing quote) that is
    /// followed by whitespace. An ellipsis written as dots ends a sentence like any other period.
    static func sentences(in text: String) -> [String] {
        var result: [String] = []
        var current = ""
        var index = text.startIndex
        while index < text.endIndex {
            let character = text[index]
            current.append(character)
            let next = text.index(after: index)
            if ".!?…".contains(character) {
                var end = next
                while end < text.endIndex, "\"'”’)".contains(text[end]) {
                    current.append(text[end])
                    end = text.index(after: end)
                }
                if end == text.endIndex || text[end].isWhitespace {
                    let sentence = current.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !sentence.isEmpty { result.append(sentence) }
                    current = ""
                }
                index = end
                continue
            }
            index = next
        }
        let rest = current.trimmingCharacters(in: .whitespacesAndNewlines)
        if !rest.isEmpty { result.append(rest) }
        return result
    }

    /// The sentence without a single closing period; an ellipsis, "!" and "?" are kept.
    static func droppingClosingPeriod(_ sentence: String) -> String {
        guard sentence.hasSuffix("."), !sentence.hasSuffix("..") else { return sentence }
        return String(sentence.dropLast())
    }

    private static let greeting = try! NSRegularExpression(
        pattern: #"^((?:hi|hello|hey|dear|good (?:morning|afternoon|evening))(?:\s+[\p{L}'’\-]+){0,3})[,.!]\s+"#,
        options: [.caseInsensitive])
    private static let signOff = try! NSRegularExpression(
        pattern: #"^((?:thanks(?: again| so much)?|thank you(?: so much)?|best(?: regards| wishes)?|kind regards|warm regards|regards|cheers|talk soon|sincerely|all the best))[,.!]?(?:\s+([\p{L}'’\-]+(?:\s+[\p{L}'’\-]+)?)[.!]?)?$"#,
        options: [.caseInsensitive])

    /// Greeting line, body paragraphs, and sign-off with the name below it.
    private static func email(_ text: String, english: Bool) -> String {
        var body = text
        var opening: String?
        if english, let match = greeting.firstMatch(in: body, range: NSRange(body.startIndex..., in: body)),
           let whole = Range(match.range, in: body), let words = Range(match.range(at: 1), in: body) {
            opening = body[words] + ","
            body = String(body[whole.upperBound...])
        }
        var sentences = Self.sentences(in: body)
        var closing: String?
        if english, let last = sentences.last,
           let match = signOff.firstMatch(in: last, range: NSRange(last.startIndex..., in: last)),
           let phrase = Range(match.range(at: 1), in: last) {
            let name = Range(match.range(at: 2), in: last).map { String(last[$0]) }
            closing = name.map { last[phrase] + ",\n" + $0 } ?? last
            sentences.removeLast()
        }
        var paragraphs: [String] = []
        var index = 0
        while index < sentences.count {
            let end = min(index + sentencesPerParagraph, sentences.count)
            paragraphs.append(sentences[index..<end].joined(separator: " "))
            index = end
        }
        if let first = paragraphs.first, let letter = first.first, letter.isLowercase {
            paragraphs[0] = letter.uppercased() + first.dropFirst()
        }
        return ([opening] + paragraphs.map(Optional.some) + [closing]).compactMap { $0 }.joined(separator: "\n\n")
    }
}
