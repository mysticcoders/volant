import Foundation

/// One word or phrase the owner wants dictation to write a particular way, such as "Kubernetes",
/// with what the recognizer tends to hear instead, such as "cooper netties".
public struct DictationVocabularyEntry: Codable, Hashable, Identifiable, Sendable {
    public var term: String
    public var soundsLike: [String]
    public var id: String { term.lowercased() }

    public init(term: String, soundsLike: [String] = []) {
        self.term = term; self.soundsLike = soundsLike
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        term = try c.decode(String.self, forKey: .term)
        soundsLike = try c.decodeIfPresent([String].self, forKey: .soundsLike) ?? []
    }
}

/// The owner's dictation vocabulary. Its terms are offered to the recognizer as hints before
/// listening, and every finished phrase is corrected afterwards: each mishearing, and the term itself
/// in any capitalization, is replaced with the term as written. Matches are whole words, ignore case,
/// and prefer the longest. Corrections apply within one phrase, so a mishearing the recognizer splits
/// across two phrases is not caught. The list is kept in config.json and never logged.
public enum DictationVocabulary {
    public static let maximumEntries = 500
    public static let maximumLength = 64
    public static let maximumSoundsLike = 8
    /// How many terms are offered to the recognizer; corrections use the whole list.
    public static let maximumHints = 100

    /// Entries trimmed and bounded: blank and overlong text dropped, mishearings that equal their term
    /// or repeat dropped, duplicate terms merged (the first spelling wins), and at most
    /// `maximumEntries` kept.
    public static func normalized(_ entries: [DictationVocabularyEntry]) -> [DictationVocabularyEntry] {
        var result: [DictationVocabularyEntry] = []
        var index: [String: Int] = [:]
        for entry in entries {
            guard let term = clean(entry.term) else { continue }
            let heard = entry.soundsLike.compactMap(clean)
            if let existing = index[term.lowercased()] {
                result[existing].soundsLike += heard
            } else {
                guard result.count < maximumEntries else { continue }
                index[term.lowercased()] = result.count
                result.append(DictationVocabularyEntry(term: term, soundsLike: heard))
            }
        }
        return result.map { entry in
            var seen: Set<String> = [entry.term.lowercased()]
            let heard = entry.soundsLike.filter { seen.insert($0.lowercased()).inserted }
            return DictationVocabularyEntry(term: entry.term, soundsLike: Array(heard.prefix(maximumSoundsLike)))
        }
    }

    /// The terms to offer the recognizer as contextual strings, at most `maximumHints`.
    public static func hints(_ entries: [DictationVocabularyEntry]) -> [String] {
        Array(normalized(entries).map(\.term).prefix(maximumHints))
    }

    /// The phrase with every mishearing and every differently capitalized term replaced by the term as
    /// written. Leading whitespace is kept so phrases still join as the recognizer spaced them.
    public static func applying(_ entries: [DictationVocabularyEntry], to phrase: String) -> String {
        guard !entries.isEmpty, !phrase.isEmpty else { return phrase }
        var replacements: [String: String] = [:]
        for entry in normalized(entries) {
            for heard in [entry.term] + entry.soundsLike where replacements[heard.lowercased()] == nil {
                replacements[heard.lowercased()] = entry.term
            }
        }
        let alternatives = replacements.keys.sorted { $0.count != $1.count ? $0.count > $1.count : $0 < $1 }
            .map { NSRegularExpression.escapedPattern(for: $0).replacingOccurrences(of: "\\ ", with: "\\s+").replacingOccurrences(of: " ", with: "\\s+") }
        guard let expression = try? NSRegularExpression(
            pattern: #"(?<![\p{L}\p{N}_])(?:"# + alternatives.joined(separator: "|") + #")(?![\p{L}\p{N}_])"#,
            options: [.caseInsensitive]) else { return phrase }
        var text = phrase
        for match in expression.matches(in: phrase, range: NSRange(phrase.startIndex..., in: phrase)).reversed() {
            guard let range = Range(match.range, in: text) else { continue }
            let found = text[range].split(whereSeparator: \.isWhitespace).joined(separator: " ").lowercased()
            guard let term = replacements[found] else { continue }
            text.replaceSubrange(range, with: term)
        }
        return text
    }

    /// Reads an imported word list. Each line is a term, or a mishearing and the term separated by a
    /// comma or tab (`cooper netties,Kubernetes`), as a two-column CSV or a replacements export has
    /// them. Blank lines, `#` comments and a `heard,written` header are skipped; quoted CSV fields are
    /// unquoted. Returns the entries and how many lines could not be used.
    public static func parse(importing text: String) -> (entries: [DictationVocabularyEntry], skipped: Int) {
        var entries: [DictationVocabularyEntry] = []
        var skipped = 0
        for raw in text.split(whereSeparator: \.isNewline) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty, !line.hasPrefix("#") else { continue }
            let fields = split(line)
            switch fields.count {
            case 1:
                guard let term = clean(fields[0]) else { skipped += 1; continue }
                entries.append(DictationVocabularyEntry(term: term))
            case 2:
                if ["heard", "spoken", "from", "original"].contains(fields[0].lowercased()) { continue }
                guard let heard = clean(fields[0]), let term = clean(fields[1]) else { skipped += 1; continue }
                entries.append(DictationVocabularyEntry(term: term, soundsLike: [heard]))
            default:
                skipped += 1
            }
        }
        return (normalized(entries), skipped)
    }

    /// Adds imported entries to an existing list: new terms are appended and known terms gain any new
    /// mishearings, within the list's limits.
    public static func merging(_ imported: [DictationVocabularyEntry], into existing: [DictationVocabularyEntry]) -> [DictationVocabularyEntry] {
        normalized(existing + imported)
    }

    /// Splits one import line on tabs, or else on commas outside double quotes.
    private static func split(_ line: String) -> [String] {
        if line.contains("\t") { return line.split(separator: "\t", omittingEmptySubsequences: false).map(String.init) }
        var fields: [String] = []
        var field = ""
        var quoted = false
        for character in line {
            if character == "\"" {
                quoted.toggle()
            } else if character == "," && !quoted {
                fields.append(field); field = ""
            } else {
                field.append(character)
            }
        }
        fields.append(field)
        return fields
    }

    /// Trimmed text with inner runs of whitespace collapsed, or nil when blank, overlong or holding a
    /// control character.
    private static func clean(_ text: String) -> String? {
        let words = text.split(whereSeparator: \.isWhitespace)
        let joined = words.joined(separator: " ")
        guard !joined.isEmpty, joined.count <= maximumLength,
              !joined.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) else { return nil }
        return joined
    }
}
