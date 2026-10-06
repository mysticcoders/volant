import Foundation

/// Integer base conversions: "255 in hex", "255 in binary", "255 in octal", "0x1F in decimal",
/// "0b1010 + 5 in hex". The left side is any calculator expression, including prefixed literals
/// ("0x1F", "0b1010", "0o17"), that comes to a whole number of at most 2^53 in size, the range a
/// calculator value holds exactly.
///
/// Negative numbers keep their sign ("-0xFF") rather than showing a two's-complement bit pattern,
/// which would need a word size the query doesn't state. Copy gives the prefixed form, so the
/// answer pastes into code. Converting to decimal requires a prefixed literal on the left, so
/// "1010 in decimal" stays a search rather than echoing its own digits back.
public enum NumberBases {
    private struct Base {
        let radix: Int
        let prefix: String
        let name: String
    }

    private static let bases: [String: Base] = {
        let hex = Base(radix: 16, prefix: "0x", name: "Hexadecimal")
        let binary = Base(radix: 2, prefix: "0b", name: "Binary")
        let octal = Base(radix: 8, prefix: "0o", name: "Octal")
        let decimal = Base(radix: 10, prefix: "", name: "Decimal")
        return ["hex": hex, "hexadecimal": hex, "binary": binary, "bin": binary, "octal": octal, "oct": octal,
                "decimal": decimal, "dec": decimal]
    }()

    private static let pattern = try! NSRegularExpression(pattern: #"^(.+?)\s+(?:in|to|as)\s+([a-z]+)$"#, options: .caseInsensitive)
    private static let literal = try! NSRegularExpression(pattern: #"^\s*0([xbo])[0-9a-f]+\s*$"#, options: .caseInsensitive)

    /// The conversion card, or nil when the query isn't a base conversion of a whole number.
    public static func evaluate(_ text: String, locale: Locale = .current) -> CalculationAnswer? {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard trimmed.utf8.count <= 256,
              let match = pattern.firstMatch(in: trimmed, range: NSRange(trimmed.startIndex..., in: trimmed)),
              let sourceRange = Range(match.range(at: 1), in: trimmed), let targetRange = Range(match.range(at: 2), in: trimmed),
              let target = bases[trimmed[targetRange].lowercased()] else { return nil }
        let source = String(trimmed[sourceRange])
        let prefixed = source.range(of: #"\b0[xbo][0-9a-f]"#, options: [.regularExpression, .caseInsensitive]) != nil
        guard target.radix != 10 || prefixed, let value = Calculator.evaluate(source, locale: locale),
              value == value.rounded(), abs(value) <= 9_007_199_254_740_992 else { return nil }
        let result = written(Int64(value), in: target)
        let origin = sourceBase(source)
        let inputDetail: String
        if let origin { inputDetail = origin.name }
        else if prefixed { inputDetail = "= " + Calculator.format(value, locale: locale) }
        else { inputDetail = bases["decimal"]!.name }
        let swap: String?
        if let origin, origin.radix != target.radix { swap = "\(result) in \(key(origin))" }
        else if !prefixed && target.radix != 10 { swap = "\(result) in decimal" }
        else { swap = nil }
        let input = trimmed.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
        return CalculationAnswer(input: input, inputDetail: inputDetail, result: grouped(result, target),
                                 resultDetail: target.name, copyText: result, swapQuery: swap)
    }

    /// The base of a left side that is a single literal: prefixed, or a plain decimal integer.
    private static func sourceBase(_ source: String) -> Base? {
        if let match = literal.firstMatch(in: source, range: NSRange(source.startIndex..., in: source)),
           let range = Range(match.range(at: 1), in: source) {
            return ["x": bases["hex"], "b": bases["binary"], "o": bases["octal"]][source[range].lowercased()] ?? nil
        }
        let digits = source.trimmingCharacters(in: .whitespaces)
        return !digits.isEmpty && digits.allSatisfy({ $0.isASCII && $0.isNumber }) ? bases["decimal"] : nil
    }

    private static func key(_ base: Base) -> String {
        switch base.radix {
        case 16: return "hex"
        case 2: return "binary"
        case 8: return "octal"
        default: return "decimal"
        }
    }

    /// Sign, prefix and digits, with hexadecimal in uppercase: "-0xFF".
    private static func written(_ value: Int64, in base: Base) -> String {
        let digits = String(value.magnitude, radix: base.radix, uppercase: true)
        return (value < 0 ? "-" : "") + base.prefix + digits
    }

    /// Binary longer than a byte shows in groups of four from the right, for reading; Copy keeps
    /// the digits together.
    private static func grouped(_ text: String, _ base: Base) -> String {
        guard base.radix == 2, let start = text.range(of: "0b") else { return text }
        let digits = Array(text[start.upperBound...])
        guard digits.count > 8 else { return text }
        var groups: [String] = []
        var end = digits.count
        while end > 0 {
            groups.insert(String(digits[max(0, end - 4)..<end]), at: 0)
            end -= 4
        }
        return text[..<start.upperBound] + groups.joined(separator: " ")
    }
}
