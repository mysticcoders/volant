import Foundation

/// Other ways to write a number, each asked for explicitly: fractions ("0.25 as fraction",
/// "1/3 + 1/6 as fraction", "2.75 as mixed number") and Roman numerals ("2026 in roman",
/// "XIV in decimal", "roman XIV").
///
/// A fraction is the closest one whose denominator is at most `maximumDenominator`, found from the
/// continued fraction and its semiconvergents, so "0.333333 as fraction" is 1/3 and pi is
/// 355/113. Answers that are not exact are tagged "Approximate". Roman numerals cover 1 to 3999 in
/// standard subtractive form only, so "IIII" and "IC" are not read; a bare numeral such as "XIV"
/// stays a search because it is also a word.
public enum NumberForms {
    static let maximumDenominator = 10_000

    private static let fraction = try! NSRegularExpression(pattern:
        #"^(.+?)\s+(?:in|to|as)\s+(?:an?\s+)?(fraction|mixed\s+(?:number|fraction))s?$"#)
    private static let toRoman = try! NSRegularExpression(pattern: #"^(.+?)\s+(?:in|to|as)\s+roman(?:\s+numerals?)?$"#)
    private static let fromRoman = try! NSRegularExpression(pattern:
        #"^(?:roman(?:\s+numerals?)?\s+([ivxlcdm]+)|([ivxlcdm]+)\s+(?:in|to|as)\s+(?:decimal|arabic|number|integer))$"#)

    public static func evaluate(_ text: String, locale: Locale = .current) -> CalculationAnswer? {
        let input = text.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
        let query = input.lowercased()
        guard query.utf8.count <= 128 else { return nil }
        if let groups = match(fraction, query), let value = Calculator.evaluate(groups[0], locale: locale) {
            return fractionAnswer(input: input, value: value, mixed: groups[1] != "fraction")
        }
        if let groups = match(toRoman, query), let value = Calculator.evaluate(groups[0], locale: locale),
           value == value.rounded(), let numeral = roman(Int(exactly: value) ?? 0) {
            return CalculationAnswer(input: input, inputDetail: nil, result: numeral, resultDetail: "Roman numeral",
                                     copyText: numeral, swapQuery: "\(numeral) in decimal")
        }
        if let groups = match(fromRoman, query), let value = integer(groups[0].isEmpty ? groups[1] : groups[0]) {
            let text = Calculator.format(Double(value), locale: locale)
            return CalculationAnswer(input: input, inputDetail: "Roman numeral", result: text,
                                     resultDetail: CalculationAnswer.spoken(Double(value), locale: locale),
                                     copyText: text, swapQuery: "\(text) in roman")
        }
        return nil
    }

    /// The fraction card: "3/2" tagged with its mixed form, or "1 1/2" tagged with the improper one.
    private static func fractionAnswer(input: String, value: Double, mixed: Bool) -> CalculationAnswer? {
        guard abs(value) < 1e12, let (numerator, denominator) = closest(value) else { return nil }
        let exact = abs(value - Double(numerator) / Double(denominator)) <= 1e-12 * max(1, abs(value))
        let improper = denominator == 1 ? "\(numerator)" : "\(numerator)/\(denominator)"
        let whole = numerator / denominator, rest = abs(numerator % denominator)
        let mixedText: String?
        if denominator == 1 || whole == 0 {
            mixedText = nil
        } else {
            mixedText = "\(whole) \(rest)/\(denominator)"
        }
        let result = mixed ? (mixedText ?? improper) : improper
        let other = mixed ? (mixedText == nil ? nil : improper) : mixedText
        let detail = [exact ? nil : "Approximate", other].compactMap { $0 }.joined(separator: " · ")
        return CalculationAnswer(input: input, inputDetail: nil, result: result, resultDetail: detail.isEmpty ? nil : detail,
                                 copyText: result)
    }

    /// The closest fraction to `value` with a denominator up to `maximumDenominator`, in lowest
    /// terms: continued-fraction convergents, then the best semiconvergent at the bound.
    static func closest(_ value: Double) -> (Int, Int)? {
        guard value.isFinite else { return nil }
        let sign = value < 0 ? -1 : 1
        let x = abs(value)
        var p0 = 0, q0 = 1, p1 = 1, q1 = 0
        var remainder = x
        for _ in 0..<64 {
            let a = remainder.rounded(.down)
            guard a < Double(Int.max / 4) else { break }
            let term = Int(a)
            let q2 = q0 + term * q1
            if q2 > maximumDenominator {
                let k = (maximumDenominator - q0) / q1
                let semi = (p0 + k * p1, q0 + k * q1)
                let best = abs(Double(semi.0) / Double(semi.1) - x) < abs(Double(p1) / Double(q1) - x) ? semi : (p1, q1)
                return (sign * best.0, best.1)
            }
            (p0, q0, p1, q1) = (p1, q1, p0 + term * p1, q2)
            let fractional = remainder - a
            if fractional < 1e-12 || abs(Double(p1) / Double(q1) - x) <= 1e-15 * max(1, x) { break }
            remainder = 1 / fractional
        }
        guard q1 > 0 else { return nil }
        return (sign * p1, q1)
    }

    private static let numerals: [(Int, String)] = [
        (1000, "M"), (900, "CM"), (500, "D"), (400, "CD"), (100, "C"), (90, "XC"),
        (50, "L"), (40, "XL"), (10, "X"), (9, "IX"), (5, "V"), (4, "IV"), (1, "I")
    ]

    /// 1 to 3999 in standard form, or nil outside that range.
    static func roman(_ value: Int) -> String? {
        guard (1...3999).contains(value) else { return nil }
        var rest = value, text = ""
        for (amount, symbol) in numerals {
            while rest >= amount { text += symbol; rest -= amount }
        }
        return text
    }

    /// Reads a numeral only when writing its value back gives the same letters, which rejects
    /// non-standard forms such as "IIII", "VX" and "IC".
    static func integer(_ numeral: String) -> Int? {
        let letters = numeral.uppercased()
        let values: [Character: Int] = ["I": 1, "V": 5, "X": 10, "L": 50, "C": 100, "D": 500, "M": 1000]
        let digits = letters.compactMap { values[$0] }
        guard !digits.isEmpty, digits.count == letters.count else { return nil }
        var total = 0
        for (index, digit) in digits.enumerated() {
            total += index + 1 < digits.count && digit < digits[index + 1] ? -digit : digit
        }
        return roman(total) == letters ? total : nil
    }

    private static func match(_ pattern: NSRegularExpression, _ text: String) -> [String]? {
        guard let result = pattern.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) else { return nil }
        return (1..<result.numberOfRanges).map { index in
            Range(result.range(at: index), in: text).map { String(text[$0]) } ?? ""
        }
    }
}
