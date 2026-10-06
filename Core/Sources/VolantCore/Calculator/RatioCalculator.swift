import Foundation

/// Ratios written with the word "ratio": "ratio of 3 to 5", "ratio 16:9", "1920:1080 ratio",
/// "4 to 6 ratio". The answer is the quotient, tagged with the percentage and the ratio in lowest
/// terms. The word is required, since "3:45" alone is a clock time and "3 to 5" alone a range.
public enum RatioCalculator {
    private static let patterns = [
        #"^ratio\s+(?:of\s+)?(.+?)\s*(?:\bto\b|:)\s*(.+)$"#,
        #"^(.+?)\s*(?:\bto\b|:)\s*(.+?)\s+ratio$"#
    ].map { try! NSRegularExpression(pattern: $0) }

    public static func evaluate(_ text: String, locale: Locale = .current) -> CalculationAnswer? {
        let input = text.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
        let query = input.lowercased()
        guard query.utf8.count <= 64 else { return nil }
        for pattern in patterns {
            guard let match = pattern.firstMatch(in: query, range: NSRange(query.startIndex..., in: query)),
                  let leftRange = Range(match.range(at: 1), in: query), let rightRange = Range(match.range(at: 2), in: query),
                  let left = NumberLiteral.parse(String(query[leftRange]), locale: locale),
                  let right = NumberLiteral.parse(String(query[rightRange]), locale: locale),
                  left >= 0, right > 0 else { continue }
            let value = left / right
            let text = Calculator.format(value, locale: locale)
            let percent = Calculator.format((value * 10_000).rounded() / 100, locale: locale) + "%"
            let detail = lowest(left, right, locale: locale).map { "\(percent) · \($0)" } ?? percent
            return CalculationAnswer(input: input, inputDetail: nil, result: text, resultDetail: detail, copyText: text)
        }
        return nil
    }

    /// The ratio in lowest whole terms, such as "16:9" for 1920 and 1080, scaling decimals up to
    /// four places first; nil when the terms are too large to read.
    static func lowest(_ left: Double, _ right: Double, locale: Locale) -> String? {
        for scale in [1.0, 10, 100, 1000, 10_000] {
            let a = (left * scale * 1e6).rounded() / 1e6, b = (right * scale * 1e6).rounded() / 1e6
            guard a == a.rounded(), b == b.rounded() else { continue }
            guard a < 1e12, b < 1e12 else { return nil }
            var x = Int(a), y = Int(b)
            while y != 0 { (x, y) = (y, x % y) }
            let divisor = Double(max(x, 1))
            return "\(Calculator.format(a / divisor, locale: locale)):\(Calculator.format(b / divisor, locale: locale))"
        }
        return nil
    }
}
