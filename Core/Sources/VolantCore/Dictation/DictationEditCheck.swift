import Foundation

/// Volant's strict check on a model's cleanup, after `TranscriptCleanupGuard`: the cleanup may only
/// make edits that can be verified against the transcript. Measured on Apple's on-device model
/// (macOS 27, 16 dictations twice), the guard alone let through "by Friday" rewritten as "by
/// wednesday" and "the coffee shop, I mean the bakery" cut to "the coffee shop", so the cleanup,
/// compared word by word with case and punctuation ignored, has to be the transcript with only
/// these edits:
/// - self-corrections: a run of up to `longestCorrection` words removed that ends with a
///   correction cue ("tuesday, no wait," or "call mom, actually,"), with words left after it, so
///   what the speaker said after the cue is what stays. A one-word cue ("no", "actually") counts
///   only when set off by a comma or a full stop, as a spoken correction is, or when the words on
///   either side are the same kind of thing (two numbers, days or months: "seven no eight");
/// - fillers removed ("um", "uh"), or a word or phrase said twice in a row removed once;
/// - words replaced by one of the speaker's vocabulary terms ("cooper netties" as "Kubernetes").
/// Anything else, an added, dropped or swapped word, rejects the whole cleanup.
public enum DictationEditCheck {
    /// The longest run of words a self-correction may remove, cue included.
    public static let longestCorrection = 10
    /// How many self-corrections one cleanup may resolve.
    public static let mostCorrections = 3

    static let phraseCues: [[String]] = [["no", "wait"], ["i", "mean"], ["scratch", "that"], ["or", "rather"], ["make", "that"]]
    static let wordCues: Set<String> = ["no", "wait", "actually", "sorry", "rather", "correction"]
    static let fillers: Set<String> = ["um", "uh", "uhm", "umm", "uhh", "er", "erm", "hmm", "mm"]

    /// Whether `cleaned` is `original` with only verifiable edits.
    public static func isAcceptable(original: String, cleaned: String, vocabulary: [String] = []) -> Bool {
        let before = tokens(original), after = tokens(cleaned).map(\.word)
        guard !after.isEmpty else { return false }
        let terms = Set(vocabulary.map { tokens($0).map(\.word).joined(separator: " ") }.filter { !$0.isEmpty })
        return matches(before, after, terms: terms, corrections: mostCorrections)
    }

    /// One word, lowercased without the punctuation around it, and whether a comma or a sentence
    /// mark sets it off on either side.
    struct Token: Equatable {
        var word: String
        var markBefore = false
        var markAfter = false
        /// A ".", "!" or "?" follows it.
        var endsSentence = false
    }

    static func tokens(_ text: String) -> [Token] {
        var result: [Token] = []
        var pendingMark = false
        for piece in text.lowercased().replacingOccurrences(of: "’", with: "'").split(whereSeparator: \.isWhitespace) {
            let raw = String(piece)
            let word = raw.split { !($0.isLetter || $0.isNumber || $0 == "'") }
                .map { $0.trimmingCharacters(in: CharacterSet(charactersIn: "'")) }
                .filter { !$0.isEmpty }
                .joined(separator: " ")
            let leading = raw.first.map { ",.;:!?—–-".contains($0) } ?? false
            let trailing = raw.last.map { ",.;:!?—–".contains($0) } ?? false
            guard !word.isEmpty else { pendingMark = pendingMark || leading || trailing; continue }
            for (index, part) in word.split(separator: " ").enumerated() {
                result.append(Token(word: String(part), markBefore: index == 0 && (pendingMark || leading), markAfter: false))
            }
            result[result.count - 1].markAfter = trailing
            result[result.count - 1].endsSentence = raw.last.map { ".!?".contains($0) } ?? false
            pendingMark = false
        }
        return result
    }

    /// Whether `after` is `before` with fillers, repeats and vocabulary replacements alone, or once
    /// up to `corrections` self-corrections are taken out of `before`.
    private static func matches(_ before: [Token], _ after: [String], terms: Set<String>, corrections: Int) -> Bool {
        if differences(before.map(\.word), after).allSatisfy({ isPlainEdit($0, in: before.map(\.word), terms: terms) }) { return true }
        guard corrections > 0 else { return false }
        for (start, end) in correctionRuns(in: before) {
            var shorter = before
            shorter.removeSubrange(start..<end)
            if matches(shorter, after, terms: terms, corrections: corrections - 1) { return true }
        }
        return false
    }

    /// Every run that a self-correction could remove: ending with a cue, at most
    /// `longestCorrection` words, starting no earlier than the sentence it is in, with words after it.
    static func correctionRuns(in tokens: [Token]) -> [(Int, Int)] {
        var runs: [(Int, Int)] = []
        for cueStart in tokens.indices {
            for length in cueLengths(at: cueStart, in: tokens) {
                let end = cueStart + length
                guard end < tokens.count else { continue }
                var start = cueStart - 1
                while start >= 0, end - start <= longestCorrection, !tokens[start].endsSentence {
                    runs.append((start, end))
                    start -= 1
                }
            }
        }
        return runs
    }

    /// The lengths of the cues that start at `index`: a phrase cue anywhere, a one-word cue only
    /// when a mark sets it off.
    private static func cueLengths(at index: Int, in tokens: [Token]) -> [Int] {
        var lengths: [Int] = []
        for cue in phraseCues where index + cue.count <= tokens.count && tokens[index..<index + cue.count].map(\.word) == cue {
            lengths.append(cue.count)
        }
        let token = tokens[index]
        let setOff = token.markBefore || token.markAfter || (index > 0 && tokens[index - 1].markAfter)
        let between = index > 0 && index + 1 < tokens.count
            && kind(of: tokens[index - 1].word).map { $0 == kind(of: tokens[index + 1].word) } == true
        if wordCues.contains(token.word), setOff || between { lengths.append(1) }
        return lengths
    }

    enum Kind { case number, day, month }

    static let numberWords: Set<String> = ["zero", "one", "two", "three", "four", "five", "six", "seven", "eight", "nine", "ten",
                                           "eleven", "twelve", "thirteen", "fourteen", "fifteen", "sixteen", "seventeen", "eighteen",
                                           "nineteen", "twenty", "thirty", "forty", "fifty", "sixty", "seventy", "eighty", "ninety",
                                           "hundred", "thousand", "million", "noon", "midnight"]
    static let days: Set<String> = ["monday", "tuesday", "wednesday", "thursday", "friday", "saturday", "sunday", "today", "tomorrow", "tonight", "yesterday"]
    static let months: Set<String> = ["january", "february", "march", "april", "may", "june", "july", "august", "september", "october", "november", "december"]

    /// What kind of thing a word names, for telling a correction ("seven no eight") from a plain "no".
    static func kind(of word: String) -> Kind? {
        if word.first?.isNumber == true || numberWords.contains(word) { return .number }
        if days.contains(word) { return .day }
        if months.contains(word) { return .month }
        return nil
    }

    /// A removal of fillers only, or of words said again right beside them; or a replacement by a
    /// vocabulary term.
    private static func isPlainEdit(_ hunk: Hunk, in original: [String], terms: Set<String>) -> Bool {
        if !hunk.inserted.isEmpty { return terms.contains(hunk.inserted.joined(separator: " ")) }
        if hunk.removed.allSatisfy(fillers.contains) { return true }
        let end = hunk.start + hunk.removed.count
        let next = Array(original[end..<min(original.count, end + hunk.removed.count)])
        let previous = Array(original[max(0, hunk.start - hunk.removed.count)..<hunk.start])
        return next == hunk.removed || previous == hunk.removed
    }

    struct Hunk: Equatable {
        /// Where the removed words start in the original.
        var start: Int
        var removed: [String]
        var inserted: [String]
    }

    /// The runs where the two word lists differ, from a longest common subsequence.
    static func differences(_ a: [String], _ b: [String]) -> [Hunk] {
        var length = Array(repeating: Array(repeating: 0, count: b.count + 1), count: a.count + 1)
        for i in stride(from: a.count - 1, through: 0, by: -1) {
            for j in stride(from: b.count - 1, through: 0, by: -1) {
                length[i][j] = a[i] == b[j] ? length[i + 1][j + 1] + 1 : max(length[i + 1][j], length[i][j + 1])
            }
        }
        var hunks: [Hunk] = []
        var current: Hunk?
        var i = 0, j = 0
        while i < a.count || j < b.count {
            if i < a.count, j < b.count, a[i] == b[j] {
                if let hunk = current { hunks.append(hunk); current = nil }
                i += 1; j += 1
            } else if j < b.count, i == a.count || length[i][j + 1] >= length[i + 1][j] {
                if current == nil { current = Hunk(start: i, removed: [], inserted: []) }
                current?.inserted.append(b[j]); j += 1
            } else {
                if current == nil { current = Hunk(start: i, removed: [], inserted: []) }
                current?.removed.append(a[i]); i += 1
            }
        }
        if let hunk = current { hunks.append(hunk) }
        return hunks
    }
}
