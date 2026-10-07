import Foundation

/// Arithmetic and percentages on amounts of money: "18% tip on $65", "20% off $80", "$65 + 18%",
/// "$1,200 / 4", "€50 + €20", "£12.50 x 4". The amounts lose their currency marks, `Calculator`
/// evaluates what remains, and the answer is formatted in that currency, so amounts in one
/// currency need no exchange rates. A tip answers the total, tagged with the tip.
///
/// Amounts in different currencies, or a target currency ("$20 + $15 in eur"), are converted with
/// the ECB rates, ExchangeRate-API rates and CoinGecko prices `CurrencyConverter` uses, from one
/// fiat source for the whole query, before the arithmetic: "10 usd + 5 eur
/// in usd", "$20 + €15" (the first currency when there is no target), "£40 - $10 in eur". Those
/// cards carry the same rate tags as conversions, and without rates there is no answer.
///
/// Money times time: an hourly rate times a duration or a plain number of hours ("$5/hr * 40",
/// "$45/hour * 37.5 hours"), and a duration times a plain amount, read as hourly ("2 hours * $40").
/// Hourly pay counts only hours, minutes and seconds, and a rate per day, week, month or year
/// multiplies only a plain number or a count of its own unit, since a working day and a calendar
/// day differ.
///
/// Marks are symbols ($ € £ ¥ ₹ and the others `CurrencyConverter` knows) before or after a number,
/// ISO codes before or after it ("usd 20", "65 USD", "USD1K", "100 aed"), coin tickers after it ("0.5 btc"),
/// and currency names ("20 dollars"). Multiplying or dividing one amount by another gives no
/// answer, since that is not an amount of money.
public enum MoneyCalculator {
    /// ISO codes that are also English words ("cup", "pen", "top", "all"), which mark an amount only
    /// in capitals ("5 CUP"), so "5 cup + 2 cup" stays a kitchen measure. The ECB's own codes keep
    /// reading in any case, as they always have.
    private static let wordCodes: Set<String> = [
        "ALK", "ALL", "ARA", "ARM", "BAD", "BAM", "BAN", "BEL", "BOB", "BOP", "CHE", "COP", "CUP", "CYP", "DOP", "GEL", "GIP",
        "LAK", "LUC", "MAD", "MOP", "MRU", "PEN", "PES", "RUB", "SAR", "SIT", "SUR", "TOP", "YER", "YUN",
        "AMD", "BTN", "CVE", "ERN", "KGS", "SOS", "STD", "XXX"
    ]
    /// Every three-letter ISO code, so amounts in currencies the ECB lacks ("100 aed", "TWD 500")
    /// work like any other; word-like codes are left to `wordCodes`.
    private static let codes: Set<String> = {
        let iso = Locale.Currency.isoCurrencies.map(\.identifier).filter { $0.count == 3 && $0.allSatisfy(\.isLetter) }
        return Set(iso).union(CurrencyRates.referenceCodes).union(["EUR"]).subtracting(wordCodes.subtracting(CurrencyRates.referenceCodes))
    }()
    /// Symbol, then code or name, on either side of a number. Only currency words are matched, so
    /// a word such as "off" in "20% off 80 usd" never takes the number from the code after it.
    private static let token: NSRegularExpression = {
        let number = #"\d(?:[\d.,]*\d)?[KMB]?"#
        let symbols = String(CurrencyConverter.symbols.keys.sorted())
        var names = codes.map { $0.lowercased() } + CryptoPrices.codes.map { $0.lowercased() }
        names.append(contentsOf: CurrencyConverter.names.keys)
        names.append(contentsOf: CryptoPrices.names.keys)
        names.sort { $0.count > $1.count }
        let words = names.joined(separator: "|")
        let prefix = codes.sorted().joined(separator: "|")
        let capitals = wordCodes.subtracting(codes).sorted().joined(separator: "|")
        return try! NSRegularExpression(pattern:
            "([\(symbols)])\\s?(\(number))|(\(number))\\s?([\(symbols)])|\\b((?i:\(prefix))|\(capitals))\\s?(\(number))"
            + "|(\(number))\\s?((?i:\(words))|\(capitals))\\b")
    }()
    private static let target = try! NSRegularExpression(pattern: #"^(.+?)\s+(?:in|to|as)\s+(\S+)$"#)
    private static let perTime = try! NSRegularExpression(pattern:
        #"^(.+?)\s*(?:/|\s+per\s+|\s+an?\s+)(hours?|hrs?|h|minutes?|mins?|days?|weeks?|wks?|months?|mo|years?|yrs?)$"#)
    private static let timeUnits: [String: String] = ["h": "hour", "hr": "hour", "min": "minute", "wk": "week", "mo": "month", "yr": "year"]

    public static func evaluate(_ text: String, rates: CurrencyRates? = CurrencyRates.current, world: WorldRates? = WorldRates.current,
                                crypto: CryptoPrices? = CryptoPrices.current, now: Date = Date(), zone: TimeZone = .current,
                                locale: Locale = .current) -> CalculationAnswer? {
        let input = text.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
        guard input.utf8.count <= 128 else { return nil }
        if let pay = timesTime(input, locale: locale) { return pay }
        let (body, to) = splitTarget(input)
        guard let (plain, found, amounts) = strip(body), amounts > 0 else { return nil }
        if found.count == 1, to == nil || to == found[0] {
            return answer(input, math: plain, code: found[0], amounts: amounts, detail: nil, locale: locale)
        }
        guard NumberLiteral.parse(plain.trimmingCharacters(in: .whitespaces), locale: locale) == nil else { return nil }
        let book = CurrencyConverter.Book(rates: rates, world: world, crypto: crypto)
        let code = to ?? found[0]
        guard let basis = book.basis(found + [code]), let toRate = book.perEuro(code, basis) else { return nil }
        var rateNotes: [String] = []
        guard let (math, _, _) = strip(body, replace: { amount, from in
            guard let fromRate = book.perEuro(from, basis), let value = Calculator.evaluate(amount, locale: locale) else { return nil }
            if from != code, !rateNotes.contains(where: { $0.hasPrefix("1 \(from) ") }) {
                rateNotes.append("1 \(from) = \(CurrencyConverter.rate(toRate / fromRate, locale: locale)) \(code)")
            }
            return "(" + Calculator.format(value / fromRate * toRate, locale: locale) + ")"
        }) else { return nil }
        let coins = (found + [code]).contains(where: CryptoPrices.codes.contains)
        let tag: String
        if coins, let crypto {
            tag = CurrencyConverter.cryptoTag(crypto.fetchedAt, now: now, zone: zone, locale: locale)
        } else if basis == .world, let world {
            tag = CurrencyConverter.worldTag(world.updated, now: now, zone: zone, locale: locale)
        } else if let rates {
            tag = CurrencyConverter.dateTag(rates.date, now: now, locale: locale)
        } else {
            return nil
        }
        guard var card = answer(input, math: math, code: code, amounts: amounts, detail: rateNotes.joined(separator: " · "), locale: locale)
        else { return nil }
        card = CalculationAnswer(input: card.input, inputDetail: card.inputDetail, result: card.result,
                                 resultDetail: card.resultDetail.map { "\($0) · \(tag)" } ?? tag, copyText: card.copyText)
        return card
    }

    /// The currencies a query would convert between before its arithmetic, so the app can fetch
    /// rates for mixed amounts on first use; nil for amounts in one currency without a target.
    static func convertedCodes(_ text: String) -> Set<String>? {
        let input = text.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
        guard input.utf8.count <= 128 else { return nil }
        let (body, to) = splitTarget(input)
        guard let (_, found, amounts) = strip(body), amounts > 0 else { return nil }
        let all = Set(found + (to.map { [$0] } ?? []))
        return all.count > 1 ? all : nil
    }

    /// The card for arithmetic whose amounts are already in one currency.
    private static func answer(_ input: String, math expression: String, code: String, amounts: Int, detail: String?,
                               locale: Locale) -> CalculationAnswer? {
        let math = expression.replacingOccurrences(of: #"(?<=[\d)])\s*[x×]\s*(?=[\d(])"#, with: " * ", options: .regularExpression)
        guard NumberLiteral.parse(math.trimmingCharacters(in: .whitespaces), locale: locale) == nil,
              amounts == 1 || math.rangeOfCharacter(from: CharacterSet(charactersIn: "*/^")) == nil,
              let value = Calculator.evaluate(math, locale: locale) else { return nil }
        let result = CurrencyConverter.money(value, code, locale: locale)
        let tip = tipAmount(math, locale: locale).map { "Tip " + CurrencyConverter.money($0, code, locale: locale) }
        return CalculationAnswer(input: input, inputDetail: detail?.isEmpty == false ? detail : nil, result: result,
                                 resultDetail: tip, copyText: result)
    }

    /// "… in eur": the arithmetic before it and the target currency, when the last word names one.
    private static func splitTarget(_ input: String) -> (String, String?) {
        guard let match = target.firstMatch(in: input, range: NSRange(input.startIndex..., in: input)),
              let body = Range(match.range(at: 1), in: input), let word = Range(match.range(at: 2), in: input),
              let code = CurrencyConverter.currency(String(input[word]), known: nil) else { return (input, nil) }
        return (String(input[body]), code)
    }

    /// The query with each amount's currency mark removed, or replaced by what `replace` returns
    /// for the amount and its currency; the currencies in order of appearance and how many amounts
    /// there were. Nil when `replace` declines an amount.
    static func strip(_ text: String, replace: ((String, String) -> String?)? = nil) -> (String, [String], Int)? {
        var output = "", cursor = text.startIndex, found: [String] = [], amounts = 0
        for match in token.matches(in: text, range: NSRange(text.startIndex..., in: text)) {
            func group(_ index: Int) -> String? {
                Range(match.range(at: index), in: text).map { String(text[$0]) }
            }
            let pairs: [(mark: Int, amount: Int)] = [(1, 2), (4, 3), (5, 6), (8, 7)]
            guard let pair = pairs.first(where: { match.range(at: $0.mark).location != NSNotFound }),
                  let mark = group(pair.mark), let amount = group(pair.amount),
                  let code = currency(mark), let whole = Range(match.range, in: text) else { continue }
            let replacement: String
            if let replace {
                guard let value = replace(amount, code) else { return nil }
                replacement = value
            } else {
                replacement = amount
            }
            output += text[cursor..<whole.lowerBound] + replacement
            cursor = whole.upperBound
            if !found.contains(code) { found.append(code) }
            amounts += 1
        }
        output += text[cursor...]
        return found.isEmpty ? nil : (output, found, amounts)
    }

    private static func currency(_ mark: String) -> String? {
        if mark.count == 1, let symbol = mark.first.flatMap({ CurrencyConverter.symbols[$0] }) { return symbol }
        if let name = CurrencyConverter.names[mark.lowercased()] ?? CryptoPrices.names[mark.lowercased()] { return name }
        let code = mark.uppercased()
        if wordCodes.contains(mark) { return mark }
        return codes.contains(code) || CryptoPrices.codes.contains(code) ? code : nil
    }

    /// The tip in "18% tip on 65", which the answer's total includes.
    private static func tipAmount(_ math: String, locale: Locale) -> Double? {
        let lowered = math.lowercased()
        guard let range = lowered.range(of: #"\btip\s+on\b"#, options: .regularExpression) else { return nil }
        return Calculator.evaluate(lowered.replacingCharacters(in: range, with: "of"), locale: locale)
    }

    /// Pay for a span of time: one side of a single `*`, `x` or `×` is an amount, the other a
    /// duration or, beside a rate, a plain number of the rate's units. The card shows the time and
    /// rate it multiplied, such as "37.5 hours at $45.00/hour".
    private static func timesTime(_ input: String, locale: Locale) -> CalculationAnswer? {
        let sides = input.components(separatedBy: CharacterSet(charactersIn: "*×"))
        let parts: [String]
        if sides.count == 2 {
            parts = sides
        } else if let range = input.range(of: #"\s+x\s+"#, options: .regularExpression) {
            parts = [String(input[..<range.lowerBound]), String(input[range.upperBound...])]
        } else {
            return nil
        }
        let trimmed = parts.map { $0.trimmingCharacters(in: .whitespaces) }
        for (moneySide, otherSide) in [(trimmed[0], trimmed[1]), (trimmed[1], trimmed[0])] {
            let (amountText, unit) = rateParts(moneySide)
            guard let (plain, found, amounts) = strip(amountText), found.count == 1, amounts == 1,
                  let amount = NumberLiteral.parse(plain.trimmingCharacters(in: .whitespaces), locale: locale) else { continue }
            let code = found[0]
            let units: Double, spoken: String
            if let unit, let (count, word) = countOf(otherSide, unit, locale: locale) {
                units = count
                spoken = word
            } else if let size = fixedSeconds[unit ?? "hour"], let seconds = durationSeconds(otherSide, clockOnly: true, locale: locale) {
                units = seconds / size
                spoken = DateCalculator.spanText(seconds)
            } else if let unit, let count = NumberLiteral.parse(otherSide, locale: locale) {
                units = count
                spoken = "\(Calculator.format(count, locale: locale)) \(unit)\(count == 1 ? "" : "s")"
            } else {
                continue
            }
            let result = CurrencyConverter.money(amount * units, code, locale: locale)
            let rate = CurrencyConverter.money(amount, code, locale: locale) + "/" + (unit ?? "hour")
            return CalculationAnswer(input: input, inputDetail: "\(spoken) at \(rate)", result: result, resultDetail: nil, copyText: result)
        }
        return nil
    }

    /// Seconds in the units whose length is fixed; days and longer depend on what counts as a day.
    private static let fixedSeconds: [String: Double] = ["hour": 3600, "minute": 60]

    /// "37.5 hours" beside a rate per hour, or "6 months" beside one per month: the count of the
    /// rate's own unit, with the words the card shows.
    private static func countOf(_ text: String, _ unit: String, locale: Locale) -> (Double, String)? {
        let words = text.lowercased().split(whereSeparator: { $0.isWhitespace }).map(String.init)
        guard words.count == 2, unitName(words[1]) == unit, let count = NumberLiteral.parse(words[0], locale: locale), count > 0 else { return nil }
        return (count, "\(Calculator.format(count, locale: locale)) \(unit)\(count == 1 ? "" : "s")")
    }

    /// "hrs" and "h" are "hour", "wks" is "week", "months" is "month".
    private static func unitName(_ raw: String) -> String {
        var name = raw.lowercased()
        if name.count > 2, name.hasSuffix("s") { name.removeLast() }
        return timeUnits[name] ?? name
    }

    /// "$45/hour" gives "$45" and "hour"; an amount without a unit of time comes back whole.
    private static func rateParts(_ text: String) -> (String, String?) {
        guard let match = perTime.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let body = Range(match.range(at: 1), in: text), let unit = Range(match.range(at: 2), in: text) else { return (text, nil) }
        return (String(text[body]), unitName(String(text[unit])))
    }

    /// Seconds in a duration written as one or more number-and-unit pairs: "2 hours", "37.5 hours",
    /// "2h 30m", "90 min". Days and weeks count as calendar days of 24 hours, unless `clockOnly`
    /// refuses them.
    static func durationSeconds(_ text: String, clockOnly: Bool = false, locale: Locale) -> Double? {
        let words = DateCalculator.normalize(text)
        guard !words.isEmpty, words.count.isMultiple(of: 2), words.count <= 8 else { return nil }
        var total = 0.0
        for index in stride(from: 0, to: words.count, by: 2) {
            guard let (_, step) = DateCalculator.quantity(words[index...(index + 1)]) else { return nil }
            switch step {
            case .seconds(let value): total += value
            case .days(let value) where !clockOnly: total += Double(value) * 86_400
            default: return nil
            }
        }
        return total > 0 ? total : nil
    }
}
