import Foundation

/// Spoken formatting for dictation, with string rules and no model: numbers said in words written
/// as digits (`SpokenNumbers`, English), punctuation said by name written as marks
/// (`SpokenPunctuation`, six languages), and spoken lists and line breaks written as lines
/// (`SpokenLists`, English and Spanish). Numbers and punctuation work within one phrase, so they
/// run on each phrase as the recognizer finishes it; a list spans phrases, so it runs on the
/// finished transcript only. Turned on and off by `Preferences.dictationFormatsSpokenText`.
public enum DictationFormatting {
    /// One finished phrase with numbers in digits and punctuation names as marks. Leading
    /// whitespace is kept so phrases still join as the recognizer spaced them, except before a
    /// mark that now starts the phrase, which attaches to the phrase before it. `protectedTerms`
    /// (the vocabulary's terms) never become digits.
    public static func formattingPhrase(_ phrase: String, locale: Locale, protectedTerms: [String] = []) -> String {
        let leading = String(phrase.prefix { $0.isWhitespace })
        let body = String(phrase.dropFirst(leading.count))
        guard !body.isEmpty else { return phrase }
        let language = locale.identifier
        let numbers = matchingCorrectedNumbers(SpokenNumbers.digits(in: body, language: language, protectedTerms: protectedTerms),
                                               language: language)
        let formatted = SpokenPunctuation.format(numbers, language: language)
        if let first = formatted.first, ",.;:!?)”»".contains(first) { return formatted }
        return leading + formatted
    }

    private static let correctedNumber = try! NSRegularExpression(
        pattern: #"(?i)\b([a-z]+(?:[- ][a-z]+){0,2})(\s*,?\s+(?:no wait|no|actually|sorry|i mean|or rather|make that)\s*,?\s+)(\$?\d[\d,.:]*)"#)

    /// A number in words taken back for one in digits ("seven, no, 8 people") is written in digits
    /// too, so a correction reads as one style when it is not resolved. The words are read with
    /// `SpokenNumbers`' own rules, as if a plural noun followed them; anything it would not turn
    /// into digits stays as said.
    static func matchingCorrectedNumbers(_ text: String, language: String) -> String {
        var result = text
        for match in correctedNumber.matches(in: text, range: NSRange(text.startIndex..., in: text)).reversed() {
            guard let wordsRange = Range(match.range(at: 1), in: result) else { continue }
            let words = String(result[wordsRange])
            for start in words.indices where start == words.startIndex || words[words.index(before: start)] == " " {
                let candidate = String(words[start...])
                let converted = SpokenNumbers.digits(in: candidate + " things", language: language)
                guard converted.hasSuffix(" things"), let first = converted.first, first.isNumber else { continue }
                let digits = String(converted.dropLast(" things".count))
                guard !digits.contains(" ") else { continue }
                let replaceFrom = result.index(wordsRange.lowerBound, offsetBy: words.distance(from: words.startIndex, to: start))
                result.replaceSubrange(replaceFrom..<wordsRange.upperBound, with: digits)
                break
            }
        }
        return result
    }

    /// A finished transcript with spoken lists and line breaks written as lines.
    public static func formattingTranscript(_ text: String, locale: Locale) -> String {
        SpokenLists.format(text, language: locale.identifier)
    }
}
