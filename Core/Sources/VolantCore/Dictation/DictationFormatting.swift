import Foundation

/// Spoken formatting for dictation, with string rules and no model: numbers said in words written
/// as digits (`SpokenNumbers`, English), punctuation said by name written as marks
/// (`SpokenPunctuation`, six languages), and spoken lists and line breaks written as lines
/// (`SpokenLists`, English and Spanish). Numbers and punctuation work within one phrase, so they
/// run on each phrase as the recognizer finishes it; a list spans phrases, so it runs on the
/// finished transcript only. A spoken correction between two numbers, days or months ("seven, no,
/// eight") is resolved to the second. Turned on and off by `Preferences.dictationFormatsSpokenText`.
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
        let formatted = resolvingCorrections(SpokenPunctuation.format(numbers, language: language), language: language)
        if let first = formatted.first, ",.;:!?)”»".contains(first) { return formatted }
        return leading + formatted
    }

    private static let spokenCorrection = try! NSRegularExpression(
        pattern: #"(?i)(?<![\p{L}\p{N}$])([\p{L}\p{N}$:.]+)[ \t]*,?[ \t]+(?:no wait|no|sorry|i mean|make that|or rather)[ \t]*,?[ \t]+([\p{L}\p{N}$:.]+?)(?=[\s,.!?;:]|$)"#)

    /// "seven, no, eight people" as "eight people": a correction cue between two words of one kind
    /// (numbers, days or months, as `DictationEditCheck.kind` reads them) keeps only the second,
    /// with the first's capital. Apple's on-device model leaves these as said when the recognizer
    /// writes no commas around the cue, and the kinds make them unambiguous, so string rules
    /// resolve them. A full stop between them still counts, since Parakeet writes the pause before
    /// the cue as one ("seven. No, eight people"); a question or exclamation keeps both ("Is it
    /// seven? No, eight."). "Actually" is no cue here ("free Tuesday, actually Wednesday works
    /// too"), and only English is read.
    static func resolvingCorrections(_ text: String, language: String) -> String {
        guard SpokenNumbers.isEnglish(language) else { return text }
        var result = text
        func kind(_ word: String) -> DictationEditCheck.Kind? {
            DictationEditCheck.kind(of: word.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "$.:")))
        }
        for match in spokenCorrection.matches(in: text, range: NSRange(text.startIndex..., in: text)).reversed() {
            guard let whole = Range(match.range, in: result), let firstRange = Range(match.range(at: 1), in: result),
                  let secondRange = Range(match.range(at: 2), in: result) else { continue }
            let first = String(result[firstRange]), second = String(result[secondRange])
            guard let firstKind = kind(first), firstKind == kind(second) else { continue }
            let kept = first.first?.isUppercase == true ? second.prefix(1).uppercased() + second.dropFirst() : second
            result.replaceSubrange(whole, with: kept)
        }
        return result
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
