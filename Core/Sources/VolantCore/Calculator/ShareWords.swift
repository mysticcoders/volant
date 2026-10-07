import Foundation

/// Shares and multiples said in words: "half of 30", "a third of 90", "two thirds of 12",
/// "a quarter of 200", "double 21", "twice 8", "triple 7". Everything after "of" (or after the
/// multiple) is the amount, so "half of 30 + 10" is 20. The amount may be a number, an expression,
/// an amount of money ("half of $80") or a duration ("half of 2 hours"), and a percentage of a
/// duration answers as a duration: "10% of 1 hour" is 6 minutes.
enum ShareWords {
    private static let fractions: [String: (Double, Double)] = [
        "half": (1, 2), "a half": (1, 2), "one half": (1, 2), "a third": (1, 3), "one third": (1, 3), "two thirds": (2, 3),
        "a quarter": (1, 4), "one quarter": (1, 4), "a fourth": (1, 4), "one fourth": (1, 4),
        "three quarters": (3, 4), "three fourths": (3, 4), "a fifth": (1, 5), "one fifth": (1, 5),
        "a tenth": (1, 10), "one tenth": (1, 10)
    ]
    private static let multiples: [String: Double] = ["double": 2, "twice": 2, "triple": 3, "thrice": 3, "quadruple": 4]
    private static let share = try! NSRegularExpression(pattern:
        #"^(half|(?:a|one)\s+(?:half|third|quarter|fourth|fifth|tenth)|two\s+thirds|three\s+(?:quarters|fourths))\s+of\s+(.+)$"#,
        options: .caseInsensitive)
    private static let multiple = try! NSRegularExpression(pattern: #"^(double|twice|triple|thrice|quadruple)\s+(.+)$"#, options: .caseInsensitive)
    private static let percent = try! NSRegularExpression(pattern: #"^(\d+(?:\.\d+)?)\s*%\s+of\s+(.+)$"#)

    static func evaluate(_ text: String, locale: Locale) -> CalculationAnswer? {
        let input = text.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
        guard input.utf8.count <= 128 else { return nil }
        if let (fraction, amount) = percentOf(input), let seconds = MoneyCalculator.durationSeconds(amount, locale: locale) {
            let text = DateCalculator.spanText(seconds * fraction)
            return CalculationAnswer(input: input, inputDetail: nil, result: text, resultDetail: nil, copyText: text)
        }
        guard let (numerator, denominator, amount) = parse(input) else { return nil }
        if let seconds = MoneyCalculator.durationSeconds(amount, locale: locale) {
            let text = DateCalculator.spanText(seconds * numerator / denominator)
            return CalculationAnswer(input: input, inputDetail: nil, result: text, resultDetail: nil, copyText: text)
        }
        let scale = " * \(Int(numerator))" + (denominator == 1 ? "" : " / \(Int(denominator))")
        if let value = Calculator.evaluate("(\(amount))" + scale, locale: locale) {
            let text = Calculator.format(value, locale: locale)
            return CalculationAnswer(input: input, inputDetail: nil, result: text,
                                     resultDetail: CalculationAnswer.spoken(value, locale: locale), copyText: text)
        }
        guard let money = MoneyCalculator.evaluate("(\(amount))" + scale, rates: nil, world: nil, crypto: nil, locale: locale) else { return nil }
        return CalculationAnswer(input: input, inputDetail: nil, result: money.result, resultDetail: nil, copyText: money.copyText)
    }

    /// The share as a fraction and the amount it applies to.
    private static func parse(_ input: String) -> (Double, Double, String)? {
        let range = NSRange(input.startIndex..., in: input)
        if let match = share.firstMatch(in: input, range: range),
           let word = Range(match.range(at: 1), in: input), let rest = Range(match.range(at: 2), in: input) {
            let key = input[word].lowercased().split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
            guard let (numerator, denominator) = fractions[key] else { return nil }
            return (numerator, denominator, String(input[rest]))
        }
        if let match = multiple.firstMatch(in: input, range: range),
           let word = Range(match.range(at: 1), in: input), let rest = Range(match.range(at: 2), in: input),
           let factor = multiples[input[word].lowercased()] {
            return (factor, 1, String(input[rest]))
        }
        return nil
    }

    /// "10% of 1 hour": the percentage as a fraction and the text after "of".
    private static func percentOf(_ input: String) -> (Double, String)? {
        guard let match = percent.firstMatch(in: input, range: NSRange(input.startIndex..., in: input)),
              let number = Range(match.range(at: 1), in: input), let rest = Range(match.range(at: 2), in: input),
              let value = Double(input[number]) else { return nil }
        return (value / 100, String(input[rest]))
    }
}
