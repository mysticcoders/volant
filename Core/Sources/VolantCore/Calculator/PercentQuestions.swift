import Foundation

/// Questions about percentages that `Calculator` cannot write as one expression: "20 is what
/// percent of 80", "what percentage is 20 of 80", "what % of 80 is 20", "20 is 25% of what",
/// "increase from 50 to 75", "50 to 75 percent change" and "3/4 in percent". Each side is an
/// ordinary calculator expression. "percent", "percentage" and "pct" read as `%`.
///
/// Percentages answer to four decimal places. A change is measured from the first value, so
/// "increase from 75 to 50" still reports the decrease it is; a change from zero has no answer.
public enum PercentQuestions {
    private static let share = try! NSRegularExpression(pattern: #"^(.+?) is what % of (.+)$"#)
    private static let shareIs = try! NSRegularExpression(pattern: #"^what % is (.+?) of (.+)$"#)
    private static let shareOf = try! NSRegularExpression(pattern: #"^what % of (.+?) is (.+)$"#)
    private static let whole = try! NSRegularExpression(pattern: #"^(.+?) is (.+?) ?% of what$"#)
    private static let changeFrom = try! NSRegularExpression(pattern:
        #"^(?:% ?)?(?:change|increase|decrease|growth|difference) from (.+?) to (.+)$"#)
    private static let changeTo = try! NSRegularExpression(pattern: #"^(?:from )?(.+?) to (.+?) (?:% ?)?change$"#)
    private static let convert = try! NSRegularExpression(pattern: #"^(.+?) (?:in|as|to) (?:a )?%$"#)

    public static func evaluate(_ text: String, locale: Locale = .current) -> CalculationAnswer? {
        guard text.utf8.count <= 256 else { return nil }
        let input = text.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
        var query = input.lowercased()
        while query.hasSuffix("?") { query.removeLast() }
        query = query.replacingOccurrences(of: #"\b(percentage|percent|pct)\b"#, with: "%", options: .regularExpression)
        query = query.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
        guard query.contains("%") || query.contains("change") || query.contains("increase") || query.contains("decrease")
                || query.contains("growth") else { return nil }
        func values(_ pattern: NSRegularExpression) -> (Double, Double)? {
            guard let match = pattern.firstMatch(in: query, range: NSRange(query.startIndex..., in: query)),
                  let first = Range(match.range(at: 1), in: query), let second = Range(match.range(at: 2), in: query),
                  let a = Calculator.evaluate(String(query[first]), locale: locale),
                  let b = Calculator.evaluate(String(query[second]), locale: locale) else { return nil }
            return (a, b)
        }
        if let (part, total) = values(share) ?? values(shareIs) ?? values(shareOf).map({ ($0.1, $0.0) }) {
            guard total != 0 else { return nil }
            let text = percent(part / total * 100, locale: locale)
            return CalculationAnswer(input: input, inputDetail: nil, result: text,
                                     resultDetail: "\(Calculator.format(part, locale: locale)) of \(Calculator.format(total, locale: locale))",
                                     copyText: text)
        }
        if let (part, rate) = values(whole) {
            guard rate != 0 else { return nil }
            let total = (part / rate * 100 * 1e10).rounded() / 1e10
            let text = Calculator.format(total, locale: locale)
            return CalculationAnswer(input: input, inputDetail: nil, result: text,
                                     resultDetail: "\(Calculator.format(rate, locale: locale))% of \(text) is \(Calculator.format(part, locale: locale))",
                                     copyText: text)
        }
        if let (from, to) = values(changeFrom) ?? values(changeTo) {
            guard from != 0 else { return nil }
            let change = (to - from) / abs(from) * 100
            let text = (change > 0 ? "+" : "") + percent(change, locale: locale)
            let amount = Calculator.format(abs(to - from), locale: locale)
            let detail = to == from ? "No change" : "\(to > from ? "Increase" : "Decrease") of \(amount)"
            return CalculationAnswer(input: input, inputDetail: nil, result: text, resultDetail: detail, copyText: text)
        }
        if let match = convert.firstMatch(in: query, range: NSRange(query.startIndex..., in: query)),
           let range = Range(match.range(at: 1), in: query), let value = Calculator.evaluate(String(query[range]), locale: locale) {
            let text = percent(value * 100, locale: locale)
            return CalculationAnswer(input: input, inputDetail: nil, result: text, resultDetail: nil, copyText: text)
        }
        return nil
    }

    /// A percentage rounded to four decimal places: "25%", "33.3333%".
    private static func percent(_ value: Double, locale: Locale) -> String {
        Calculator.format((value * 10_000).rounded() / 10_000, locale: locale) + "%"
    }
}
