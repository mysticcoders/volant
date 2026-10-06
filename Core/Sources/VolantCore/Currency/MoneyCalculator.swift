import Foundation

/// Arithmetic and percentages on amounts in one currency: "18% tip on $65", "20% off $80",
/// "$65 + 18%", "$1,200 / 4", "€50 + €20", "£12.50 x 4". The amounts lose their currency marks,
/// `Calculator` evaluates what remains, and the answer is formatted in that currency, so no
/// exchange rates are needed. A tip answers the total, tagged with the tip.
///
/// Marks are symbols ($ € £ ¥ ₹ ₩ ₺) before or after a number, the codes of the ECB reference
/// currencies before or after it ("usd 20", "65 USD", "USD1K"), and currency names ("20 dollars").
/// Mixing currencies gives no answer, as does multiplying or dividing one amount by another,
/// since that is not an amount of money.
public enum MoneyCalculator {
    private static let codes: Set<String> = [
        "EUR", "USD", "JPY", "BGN", "CZK", "DKK", "GBP", "HUF", "PLN", "RON", "SEK", "CHF", "ISK", "NOK", "TRY", "AUD",
        "BRL", "CAD", "CNY", "HKD", "IDR", "ILS", "INR", "KRW", "MXN", "MYR", "NZD", "PHP", "SGD", "THB", "ZAR"
    ]
    /// Symbol, then code or name, on either side of a number. Only currency words are matched, so
    /// a word such as "off" in "20% off 80 usd" never takes the number from the code after it.
    private static let token: NSRegularExpression = {
        let number = #"\d(?:[\d.,]*\d)?[KMB]?"#
        var names = codes.map { $0.lowercased() }
        names.append(contentsOf: CurrencyConverter.names.keys)
        names.sort { $0.count > $1.count }
        let words = names.joined(separator: "|")
        let prefix = codes.sorted().joined(separator: "|")
        return try! NSRegularExpression(pattern:
            "([$€£¥₹₩₺])\\s?(\(number))|(\(number))\\s?([$€£¥₹₩₺])|\\b(?i:(\(prefix)))\\s?(\(number))|(\(number))\\s?(?i:(\(words)))\\b")
    }()

    public static func evaluate(_ text: String, locale: Locale = .current) -> CalculationAnswer? {
        let input = text.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
        guard input.utf8.count <= 128, let (expression, code, amounts) = strip(input), amounts > 0 else { return nil }
        let math = expression.replacingOccurrences(of: #"(?<=[\d)])\s*[x×]\s*(?=[\d(])"#, with: " * ", options: .regularExpression)
        guard NumberLiteral.parse(math.trimmingCharacters(in: .whitespaces), locale: locale) == nil,
              amounts == 1 || math.rangeOfCharacter(from: CharacterSet(charactersIn: "*/^")) == nil,
              let value = Calculator.evaluate(math, locale: locale) else { return nil }
        let result = CurrencyConverter.money(value, code, locale: locale)
        let tip = tipAmount(math, locale: locale).map { "Tip " + CurrencyConverter.money($0, code, locale: locale) }
        return CalculationAnswer(input: input, inputDetail: nil, result: result, resultDetail: tip, copyText: result)
    }

    /// The query with each amount's currency mark removed, the one currency they share and how
    /// many amounts there were; nil when amounts name different currencies.
    static func strip(_ text: String) -> (String, String, Int)? {
        var output = "", cursor = text.startIndex, found: Set<String> = [], amounts = 0
        for match in token.matches(in: text, range: NSRange(text.startIndex..., in: text)) {
            func group(_ index: Int) -> String? {
                Range(match.range(at: index), in: text).map { String(text[$0]) }
            }
            let pairs: [(mark: Int, amount: Int)] = [(1, 2), (4, 3), (5, 6), (8, 7)]
            guard let pair = pairs.first(where: { match.range(at: $0.mark).location != NSNotFound }),
                  let mark = group(pair.mark), let amount = group(pair.amount),
                  let code = currency(mark), let whole = Range(match.range, in: text) else { continue }
            output += text[cursor..<whole.lowerBound] + amount
            cursor = whole.upperBound
            found.insert(code)
            amounts += 1
        }
        output += text[cursor...]
        guard found.count == 1, let code = found.first else { return nil }
        return (output, code, amounts)
    }

    private static func currency(_ mark: String) -> String? {
        if mark.count == 1, let symbol = mark.first.flatMap({ CurrencyConverter.symbols[$0] }) { return symbol }
        if let name = CurrencyConverter.names[mark.lowercased()] { return name }
        return codes.contains(mark.uppercased()) ? mark.uppercased() : nil
    }

    /// The tip in "18% tip on 65", which the answer's total includes.
    private static func tipAmount(_ math: String, locale: Locale) -> Double? {
        let lowered = math.lowercased()
        guard let range = lowered.range(of: #"\btip\s+on\b"#, options: .regularExpression) else { return nil }
        return Calculator.evaluate(lowered.replacingCharacters(in: range, with: "of"), locale: locale)
    }
}
