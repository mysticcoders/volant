import Foundation

/// Catches mishearings of vocabulary words that the owner never listed, by sound: "Kubernitz" and
/// "Gubanits" both become "Kubernetes" when Kubernetes is in the vocabulary. Only words the spell
/// checker does not know are considered, so ordinary speech is left alone; a mishearing made of real
/// words, such as "herder" for Herdr or "tail scale" for Tailscale, still needs an explicit
/// "Also heard as". A candidate is one to three adjacent words joined by spaces or hyphens, at least
/// one of them unknown, and it must sound like a term of at least five letters (`phoneticKey`: the
/// same sound skeleton, or one sound off when the skeleton has six or more) and share enough of its
/// spelling. Overlapping candidates are resolved closest first.
public enum DictationCloseMatch {
    public static let minimumTermLetters = 5
    public static let maximumSpanWords = 3
    /// Sound skeletons this long or longer may differ by one sound; shorter ones must be equal.
    static let lengthAllowingOneSoundOff = 6
    static let minimumSpellingScore = 0.45

    /// The phrase with close matches replaced. `isKnownWord` answers for one word as it appears; the
    /// app backs it with the system spell checker.
    public static func correcting(_ entries: [DictationVocabularyEntry], in phrase: String, isKnownWord: (String) -> Bool) -> String {
        let terms = DictationVocabulary.normalized(entries).map(\.term).filter { letters($0).count >= minimumTermLetters }
        guard !terms.isEmpty else { return phrase }
        let termKeys = terms.map { (term: $0, key: phoneticKey($0), letters: letters($0)) }
        let known = Set(terms.map { $0.lowercased() })
        let words = tokens(in: phrase)
        guard !words.isEmpty else { return phrase }
        var unknown: [Bool] = []
        for word in words {
            let text = String(phrase[word.range])
            unknown.append(!known.contains(text.lowercased()) && !text.allSatisfy(\.isNumber) && !isKnownWord(text))
        }

        var candidates: [(start: Int, end: Int, term: String, score: Int)] = []
        for start in words.indices {
            for end in start..<min(words.count, start + maximumSpanWords) {
                if end > start && !words[end].joinsPrevious { break }
                guard unknown[start...end].contains(true) else { continue }
                let spoken = words[start...end].map { String(phrase[$0.range]) }.joined()
                let spokenKey = phoneticKey(spoken), spokenLetters = letters(spoken)
                guard spokenKey.count >= 3 else { continue }
                for term in termKeys {
                    let soundsOff = distance(spokenKey, term.key)
                    guard soundsOff <= (max(spokenKey.count, term.key.count) >= lengthAllowingOneSoundOff ? 1 : 0),
                          similarity(spokenLetters, term.letters) >= minimumSpellingScore, spokenLetters != term.letters else { continue }
                    candidates.append((start, end, term.term, soundsOff))
                }
            }
        }
        candidates.sort { $0.score != $1.score ? $0.score < $1.score : ($0.end - $0.start) < ($1.end - $1.start) }
        var taken = Set<Int>()
        var chosen: [(range: Range<String.Index>, term: String)] = []
        for candidate in candidates where !(candidate.start...candidate.end).contains(where: taken.contains) {
            taken.formUnion(candidate.start...candidate.end)
            chosen.append((words[candidate.start].range.lowerBound..<words[candidate.end].range.upperBound, candidate.term))
        }
        var text = phrase
        for choice in chosen.sorted(by: { $0.range.lowerBound > $1.range.lowerBound }) {
            text.replaceSubrange(choice.range, with: choice.term)
        }
        return text
    }

    /// A rough English sound skeleton: voiced and unvoiced pairs merged (b/p, d/t, g/k, v/f, z/s),
    /// soft and hard c resolved, ph, ck, q and x spelled out, h dropped, vowels kept only as a leading
    /// marker, an r before a consonant or at the end dropped, and repeats collapsed. "Kubernetes",
    /// "Kubernitz" and "Gubanits" all read as "kpnts".
    public static func phoneticKey(_ text: String) -> String {
        var source = letters(text)
        for (from, to) in [("ph", "f"), ("ck", "k"), ("qu", "kw"), ("sch", "sk"), ("gh", ""), ("x", "ks")] {
            source = source.replacingOccurrences(of: from, with: to)
        }
        let chars = Array(source)
        var mapped: [Character] = []
        for (index, char) in chars.enumerated() {
            let next = index + 1 < chars.count ? chars[index + 1] : nil
            switch char {
            case "a", "e", "i", "o", "u", "y": mapped.append(index == 0 ? "a" : "·")
            case "c": mapped.append(next.map { "eiy".contains($0) } == true ? "s" : "k")
            case "q", "g": mapped.append("k")
            case "b": mapped.append("p")
            case "d": mapped.append("t")
            case "v": mapped.append("f")
            case "z": mapped.append("s")
            case "h": continue
            default: mapped.append(char)
            }
        }
        var key: [Character] = []
        for (index, char) in mapped.enumerated() {
            if char == "·" { continue }
            if char == "r" && !(index + 1 < mapped.count && mapped[index + 1] == "·") { continue }
            if key.last != char { key.append(char) }
        }
        return String(key)
    }

    /// The edit distance between two strings: insertions, deletions and substitutions.
    static func distance(_ a: String, _ b: String) -> Int {
        let a = Array(a), b = Array(b)
        guard !a.isEmpty, !b.isEmpty else { return max(a.count, b.count) }
        var previous = Array(0...b.count)
        for i in 1...a.count {
            var current = [i] + Array(repeating: 0, count: b.count)
            for j in 1...b.count {
                current[j] = min(previous[j] + 1, current[j - 1] + 1, previous[j - 1] + (a[i - 1] == b[j - 1] ? 0 : 1))
            }
            previous = current
        }
        return previous[b.count]
    }

    /// One minus the edit distance over the longer length: 1 for equal strings.
    static func similarity(_ a: String, _ b: String) -> Double {
        guard !a.isEmpty || !b.isEmpty else { return 1 }
        return 1 - Double(distance(a, b)) / Double(max(a.count, b.count))
    }

    static func letters(_ text: String) -> String {
        String(text.lowercased().filter { $0.isLetter && $0.isASCII })
    }

    /// Runs of letters, digits and apostrophes, each noting whether only spaces or a hyphen separate it
    /// from the previous one, so a span never crosses punctuation.
    private static func tokens(in phrase: String) -> [(range: Range<String.Index>, joinsPrevious: Bool)] {
        var result: [(range: Range<String.Index>, joinsPrevious: Bool)] = []
        var index = phrase.startIndex
        var gap = ""
        while index < phrase.endIndex {
            let char = phrase[index]
            if char.isLetter || char.isNumber || char == "'" || char == "’" {
                var end = phrase.index(after: index)
                while end < phrase.endIndex, phrase[end].isLetter || phrase[end].isNumber || phrase[end] == "'" || phrase[end] == "’" {
                    end = phrase.index(after: end)
                }
                let joins = !result.isEmpty && gap.allSatisfy { $0 == " " || $0 == "-" } && gap.filter { $0 == "-" }.count <= 1
                result.append((index..<end, joins))
                gap = ""
                index = end
            } else {
                gap.append(char)
                index = phrase.index(after: index)
            }
        }
        return result
    }
}
