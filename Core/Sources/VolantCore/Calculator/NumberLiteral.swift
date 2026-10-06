import Foundation

/// Numbers as the owner's locale writes them, shared by the calculator and unit converter.
///
/// The locale's grouping separator is accepted only between groups of three digits ("1,000",
/// "12,345,678"), so "1,5" is rejected in English rather than read as a list or a decimal. The
/// decimal separator is the locale's: "2,5" in German, where "1.000" is a thousand. Scientific
/// notation ("1e3", "2.5E-3") and magnitude suffixes ("10K", "2.5M", "1B") are accepted;
/// lowercase m and b stay free for meters and bytes. The calculator also reads magnitude words,
/// counts among them ("2.5 million", "2 dozen", "3 gross").
public enum NumberLiteral {
    static let suffixes: [Character: Double] = ["k": 1e3, "K": 1e3, "M": 1e6, "B": 1e9]
    static let words: [String: Double] = ["thousand": 1e3, "million": 1e6, "billion": 1e9, "dozen": 12, "gross": 144]

    struct Separators {
        let decimal: Character
        let grouping: Character
        /// Locales that group with a space (often a non-breaking one) accept a typed ordinary space.
        let spaceGrouping: Bool

        init(_ locale: Locale) {
            decimal = locale.decimalSeparator?.first ?? "."
            let group = locale.groupingSeparator?.first ?? ","
            grouping = group == decimal ? (decimal == "." ? "," : ".") : group
            spaceGrouping = grouping.isWhitespace
        }

        func groups(_ character: Character) -> Bool {
            character == grouping || (spaceGrouping && character.isWhitespace && !character.isNewline)
        }
    }

    /// Reads a whole literal such as "1,000.5", "2,5", "1e3" or "10K". Anything else is nil.
    public static func parse(_ text: String, locale: Locale, magnitudes: Bool = true) -> Double? {
        let chars = Array(text)
        guard let (value, end) = scan(chars, from: 0, Separators(locale), magnitudes: magnitudes), end == chars.count else { return nil }
        return value
    }

    /// Scans a literal starting at `start` and returns its value and the index after it, or nil
    /// when no valid number starts there. Units turn magnitudes off, since "100k" there is kelvin;
    /// function arguments can turn grouping off, so "max(1,5)" reads the comma as a separator.
    static func scan(_ chars: [Character], from start: Int, _ separators: Separators, magnitudes: Bool = true,
                     grouping: Bool = true) -> (Double, Int)? {
        func digit(_ index: Int) -> Bool { index < chars.count && chars[index].isASCII && chars[index].isNumber }
        guard digit(start) || (start < chars.count && chars[start] == separators.decimal && digit(start + 1)) else { return nil }
        var index = start
        var mantissa = ""
        var groups: [Int] = []
        var current = 0
        var fraction: String?
        while index < chars.count {
            let ch = chars[index]
            if digit(index) {
                if fraction != nil { fraction! += String(ch) } else { mantissa += String(ch); current += 1 }
            } else if ch == separators.decimal, fraction == nil, digit(index + 1) {
                fraction = ""
            } else if grouping, separators.groups(ch), fraction == nil, digit(index + 1) {
                groups.append(current)
                current = 0
            } else {
                break
            }
            index += 1
        }
        if !groups.isEmpty {
            groups.append(current)
            guard (1...3).contains(groups[0]), groups.dropFirst().allSatisfy({ $0 == 3 }) else { return nil }
        }
        var literal = (mantissa.isEmpty ? "0" : mantissa) + (fraction.map { "." + $0 } ?? "")
        if index < chars.count, chars[index] == "e" || chars[index] == "E" {
            var next = index + 1
            var exponent = "e"
            if next < chars.count, chars[next] == "+" || chars[next] == "-" { exponent += String(chars[next]); next += 1 }
            if digit(next) {
                while digit(next) { exponent += String(chars[next]); next += 1 }
                literal += exponent
                index = next
            }
        }
        guard var value = Double(literal) else { return nil }
        if magnitudes, index < chars.count, let scale = suffixes[chars[index]], !(index + 1 < chars.count && chars[index + 1].isLetter) {
            value *= scale
            index += 1
        }
        return (value, index)
    }
}
