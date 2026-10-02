import Foundation

/// One calculator card: the query as the owner wrote it and its answer, each with an optional
/// detail tag, plus the single line Copy puts on the clipboard.
public struct CalculationAnswer: Hashable {
    public let input: String
    public let inputDetail: String?
    public let result: String
    public let resultDetail: String?
    public let copyText: String

    public init(input: String, inputDetail: String?, result: String, resultDetail: String?, copyText: String) {
        self.input = input
        self.inputDetail = inputDetail
        self.result = result
        self.resultDetail = resultDetail
        self.copyText = copyText
    }

    /// Every answer the query has, in the order the launcher lists them: time conversion,
    /// arithmetic, then unit conversion. The input side keeps the owner's wording, trimmed.
    public static func answers(for query: String, now: Date = Date(), localZone: TimeZone = .current,
                               locale: Locale = .current) -> [CalculationAnswer] {
        let input = query.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
        var answers: [CalculationAnswer] = []
        if let time = TimeCalculator.evaluate(query, now: now, localZone: localZone, locale: locale) {
            answers.append(CalculationAnswer(input: input, inputDetail: time.source, result: time.headline,
                                             resultDetail: time.detail, copyText: time.text))
        }
        if let value = Calculator.evaluate(query) {
            let text = Calculator.format(value)
            answers.append(CalculationAnswer(input: input, inputDetail: nil, result: text,
                                             resultDetail: spoken(value, locale: locale), copyText: text))
        }
        if let conversion = UnitConverter.convert(query) {
            let result = UnitConverter.formatResult(conversion)
            answers.append(CalculationAnswer(input: "\(Calculator.format(conversion.value)) \(conversion.fromSymbol)",
                                             inputDetail: unitName(conversion.fromUnit, locale: locale), result: result,
                                             resultDetail: unitName(conversion.toUnit, locale: locale), copyText: result))
        }
        return answers
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
