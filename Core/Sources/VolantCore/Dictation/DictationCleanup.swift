import Foundation

/// Removes spoken filler words such as "um" and "uh" from dictated English text, one phrase at a
/// time, so it can run on each phrase as the recognizer finishes it. Only sounds that never carry
/// meaning are removed; words like "like", "you know" and "I mean" stay, and so do "uh-oh",
/// "uh-huh", "mhm", "err" and all-capitals acronyms such as "ER". Commas around a removed filler, the spaces it leaves, and the capital it
/// took from the start of a sentence are repaired. Other languages are returned unchanged.
public enum DictationCleanup {
    private static let filler = try! NSRegularExpression(
        pattern: #"(,\s*)?(?<![\p{L}\p{N}'’\-])(u+m+|u+h+m+|u+h+|erm+|er|h+m+)(?![\p{L}\p{N}'’\-])(\s*,)?"#,
        options: [.caseInsensitive])
    private static let extraSpaces = try! NSRegularExpression(pattern: #"[ \t]{2,}"#)
    private static let spaceBeforePunctuation = try! NSRegularExpression(pattern: #"[ \t]+([,.!?;:])"#)
    private static let leadingPunctuation = try! NSRegularExpression(pattern: #"^[ \t]*[,;:.!?][ \t]*"#)
    /// A sentence end left alone after its filler sentence was removed: "check. . Yes" (not "...").
    private static let repeatedSentenceEnd = try! NSRegularExpression(pattern: #"([.!?])[ \t]+[.!?](?=[ \t]|$)"#)

    /// Whether cleanup applies to dictation in this locale.
    public static func supports(_ locale: Locale) -> Bool {
        locale.language.languageCode?.identifier == "en"
    }

    /// The phrase without filler words. Leading whitespace is kept so phrases still join as the
    /// recognizer spaced them; a phrase that was only filler becomes empty.
    public static func removingFillers(_ phrase: String, locale: Locale) -> String {
        guard supports(locale) else { return phrase }
        let leading = String(phrase.prefix { $0 == " " || $0 == "\t" })
        var text = String(phrase.dropFirst(leading.count))
        let matches = filler.matches(in: text, range: NSRange(text.startIndex..., in: text))
        guard !matches.isEmpty else { return phrase }
        // Right to left, so each replacement leaves the ranges of earlier matches valid.
        for match in matches.reversed() {
            guard let whole = Range(match.range, in: text), let word = Range(match.range(at: 2), in: text) else { continue }
            let commaBefore = match.range(at: 1).location != NSNotFound
            let commaAfter = match.range(at: 3).location != NSNotFound
            let startsSentence = text[..<whole.lowerBound].trimmingCharacters(in: .whitespaces).last.map { ".!?".contains($0) } ?? true
            // An all-capitals "ER" or "UM" is more likely an acronym than a sound.
            if text[word].count > 1 && text[word].allSatisfy({ $0.isUppercase }) { continue }
            let capitalized = text[word].first?.isUppercase == true
            let replacement = commaBefore && commaAfter ? ", " : (commaBefore || commaAfter) && !startsSentence ? " " : ""
            let offset = text.distance(from: text.startIndex, to: whole.lowerBound)
            text.replaceSubrange(whole, with: replacement)
            guard startsSentence && capitalized else { continue }
            let start = text.index(text.startIndex, offsetBy: offset)
            if let letter = text[start...].firstIndex(where: { $0.isLetter }),
               text[start..<letter].allSatisfy({ $0 == " " || $0 == "\t" || $0 == "," }) {
                text.replaceSubrange(letter...letter, with: text[letter].uppercased())
            }
        }
        text = replace(extraSpaces, in: text, with: " ")
        text = replace(repeatedSentenceEnd, in: text, with: "$1")
        text = replace(spaceBeforePunctuation, in: text, with: "$1")
        text = replace(leadingPunctuation, in: text, with: "")
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return "" }
        return leading + String(text.drop { $0 == " " || $0 == "\t" })
    }

    private static func replace(_ expression: NSRegularExpression, in text: String, with template: String) -> String {
        expression.stringByReplacingMatches(in: text, range: NSRange(text.startIndex..., in: text), withTemplate: template)
    }
}
