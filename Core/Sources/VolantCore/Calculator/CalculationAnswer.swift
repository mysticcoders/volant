import Foundation

/// One calculator card: the query as the owner wrote it and its answer, each with an optional
/// detail tag, plus the single line Copy puts on the clipboard.
public struct CalculationAnswer: Hashable {
    public let input: String
    public let inputDetail: String?
    public let result: String
    public let resultDetail: String?
    public let copyText: String
    /// A color to show beside the input, for color conversions.
    public let swatch: Swatch?
    /// The same conversion in the other direction, for Shift-Command-Return: "3.106856 mi in km".
    public let swapQuery: String?

    /// An sRGB color with components from 0 to 1.
    public struct Swatch: Hashable {
        public let red: Double
        public let green: Double
        public let blue: Double
        public let alpha: Double

        public init(red: Double, green: Double, blue: Double, alpha: Double) {
            self.red = red
            self.green = green
            self.blue = blue
            self.alpha = alpha
        }
    }

    public init(input: String, inputDetail: String?, result: String, resultDetail: String?, copyText: String,
                swatch: Swatch? = nil, swapQuery: String? = nil) {
        self.input = input
        self.inputDetail = inputDetail
        self.result = result
        self.resultDetail = resultDetail
        self.copyText = copyText
        self.swatch = swatch
        self.swapQuery = swapQuery
    }

    /// Every answer the query has, in the order the launcher lists them: time conversion, dates
    /// and durations, colors and color adjustments, fractions and Roman numerals, number bases, ratios, arithmetic,
    /// then unit conversion. The input side keeps the owner's wording, trimmed.
    public static func answers(for query: String, now: Date = Date(), localZone: TimeZone = .current,
                               locale: Locale = .current) -> [CalculationAnswer] {
        let query = forgiving(query)
        let input = query.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
        var answers: [CalculationAnswer] = []
        if let time = TimeCalculator.evaluate(query, now: now, localZone: localZone, locale: locale) {
            answers.append(CalculationAnswer(input: input, inputDetail: time.source, result: time.headline,
                                             resultDetail: time.detail, copyText: time.text, swapQuery: time.swap))
        } else {
            for suggestion in TimeCalculator.suggestions(query, now: now, localZone: localZone, locale: locale) {
                answers.append(CalculationAnswer(input: suggestion.query, inputDetail: suggestion.result.source,
                                                 result: suggestion.result.headline, resultDetail: suggestion.result.detail,
                                                 copyText: suggestion.result.text))
            }
        }
        if let date = DateCalculator.evaluate(query, now: now, localZone: localZone, locale: locale) {
            answers.append(date)
        }
        if let color = ColorCalculator.evaluate(query) {
            answers.append(color)
        }
        if let adjusted = ColorAdjustments.evaluate(query, locale: locale) {
            answers.append(adjusted)
        }
        if let form = NumberForms.evaluate(query, locale: locale) {
            answers.append(form)
        }
        if let base = NumberBases.evaluate(query, locale: locale) {
            answers.append(base)
        }
        if let ratio = RatioCalculator.evaluate(query, locale: locale) {
            answers.append(ratio)
        }
        let closed = Calculator.closingParentheses(query)
        if let value = Calculator.evaluate(closed, locale: locale) {
            let text = Calculator.format(value, locale: locale)
            let shown = closed == query ? input : closed.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
            answers.append(CalculationAnswer(input: shown, inputDetail: nil, result: text,
                                             resultDetail: tip(query, locale: locale) ?? spoken(value, locale: locale), copyText: text))
        }
        if let screen = ScreenUnits.evaluate(query, locale: locale) {
            answers.append(screen)
        }
        if let money = CurrencyConverter.evaluate(query, now: now, zone: localZone, locale: locale) {
            answers.append(money)
        }
        if let money = MoneyCalculator.evaluate(query, locale: locale) {
            answers.append(money)
        }
        if let conversion = UnitConverter.convert(query, locale: locale) {
            let result = UnitConverter.formatResult(conversion, locale: locale)
            answers.append(CalculationAnswer(input: UnitConverter.formatSource(conversion, locale: locale),
                                             inputDetail: unitName(conversion.fromUnit, locale: locale), result: result,
                                             resultDetail: unitName(conversion.toUnit, locale: locale), copyText: result,
                                             swapQuery: UnitConverter.swapQuery(conversion, locale: locale)))
        }
        return answers
    }

    /// Drops the framing people type around a question: a leading "what is", "what's" or
    /// "calculate", and trailing "=" or "?" marks, so "what is 5 + 5?" reads as "5 + 5".
    static func forgiving(_ query: String) -> String {
        var text = query.trimmingCharacters(in: .whitespaces)
        if let range = text.range(of: #"^(what\s+is|what['’]?s|calculate)\s+"#, options: [.regularExpression, .caseInsensitive]) {
            text.removeSubrange(range)
        }
        while let last = text.last, last == "=" || last == "?" || last.isWhitespace { text.removeLast() }
        return text.isEmpty ? query : text
    }

    /// "15% tip on 42" answers the total, so the tag names the tip itself.
    static func tip(_ query: String, locale: Locale) -> String? {
        let lowered = query.lowercased()
        guard let range = lowered.range(of: #"\btip\s+on\b"#, options: .regularExpression),
              let amount = Calculator.evaluate(lowered.replacingCharacters(in: range, with: "of"), locale: locale) else { return nil }
        return "Tip " + Calculator.format(amount, locale: locale)
    }

    /// Small whole numbers read as words; larger ones gain thousands separators. Fractions and
    /// numbers that already read plainly get no detail.
    static func spoken(_ value: Double, locale: Locale) -> String? {
        guard value.isFinite, value == value.rounded() else { return nil }
        let formatter = NumberFormatter()
        formatter.locale = locale
        if abs(value) < 10_000 {
            formatter.numberStyle = .spellOut
            return formatter.string(from: NSNumber(value: value)).map(capitalizedFirst)
        }
        guard abs(value) < 1e15 else { return nil }
        formatter.numberStyle = .decimal
        return formatter.string(from: NSNumber(value: value))
    }

    static func unitName(_ unit: Dimension?, locale: Locale) -> String? {
        guard let unit else { return nil }
        if unit is UnitCount, UnitConverter.name(of: unit) == nil { return nil }
        if let custom = UnitConverter.name(of: unit) { return custom }
        let formatter = MeasurementFormatter()
        formatter.locale = locale
        formatter.unitStyle = .long
        formatter.unitOptions = .providedUnit
        let name = formatter.string(from: unit)
        return name.isEmpty ? nil : capitalizedFirst(name)
    }

    private static func capitalizedFirst(_ text: String) -> String {
        text.prefix(1).uppercased() + text.dropFirst()
    }
}
