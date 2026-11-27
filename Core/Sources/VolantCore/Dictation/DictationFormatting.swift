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
        let formatted = SpokenPunctuation.format(SpokenNumbers.digits(in: body, language: language, protectedTerms: protectedTerms),
                                                 language: language)
        if let first = formatted.first, ",.;:!?)”»".contains(first) { return formatted }
        return leading + formatted
    }

    /// A finished transcript with spoken lists and line breaks written as lines.
    public static func formattingTranscript(_ text: String, locale: Locale) -> String {
        SpokenLists.format(text, language: locale.identifier)
    }
}
