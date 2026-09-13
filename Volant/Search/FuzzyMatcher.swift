import Foundation

/// Subsequence matcher with bonuses for prefix, word-start, and consecutive hits. Higher is better; nil is no match.
/// Scores two alignments, plain greedy and word-start-preferring, and keeps the better one so acronyms win.
enum FuzzyMatcher {
    static func score(query: String, candidate: String) -> Int? {
        let q = Array(query.lowercased())
        let c = Array(candidate.lowercased())
        let original = Array(candidate)
        if q.isEmpty { return 0 }
        if q.count > c.count { return nil }
        let greedy = align(q, c, original, preferWordStarts: false)
        let starts = align(q, c, original, preferWordStarts: true)
        guard let best = [greedy, starts].compactMap({ $0 }).max() else { return nil }
        var score = best - max(0, c.count - q.count) / 2
        if candidate.lowercased().hasPrefix(query.lowercased()) { score += 40 }
        return score
    }

    private static func align(_ q: [Character], _ c: [Character], _ original: [Character], preferWordStarts: Bool) -> Int? {
        var score = 0
        var lastHit = -2
        var from = 0
        for ch in q {
            var hit: Int? = nil
            if preferWordStarts {
                hit = (from..<c.count).first { c[$0] == ch && isWordStart(original, at: $0) }
            }
            if hit == nil {
                hit = (from..<c.count).first { c[$0] == ch }
            }
            guard let ci = hit else { return nil }
            var gain = 10
            if ci == 0 { gain += 30 } else if isWordStart(original, at: ci) { gain += 20 }
            if ci == lastHit + 1 { gain += 15 }
            score += gain
            lastHit = ci
            from = ci + 1
        }
        return score
    }

    private static func isWordStart(_ chars: [Character], at index: Int) -> Bool {
        guard index > 0 else { return true }
        let prev = chars[index - 1]
        return prev == " " || prev == "-" || prev == "_" || prev == "." || (prev.isLowercase && chars[index].isUppercase)
    }
}
