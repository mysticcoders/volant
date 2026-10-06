import Foundation

/// Currency conversion with ECB reference rates: "100 usd in eur", "$100 in gbp", "€50 to yen",
/// "USD1K in CHF", "20 pounds in euros". Cross rates go through the euro. The card tags the rate
/// date, so cached rates are never mistaken for live prices; without rates there is no answer.
///
/// Symbols and names map to one currency each ($ and dollars are US dollars, ¥ and yen are
/// Japanese yen); other dollars and pesos need their ISO code. "pounds" is currency only when the
/// other side is a currency, so "5 pounds in kg" stays a weight.
///
/// With `CryptoPrices` from CoinGecko, major coins convert too ("0.5 btc in usd",
/// "100 eur in eth"), through their euro price; those cards tag CoinGecko and the fetch time.
public enum CurrencyConverter {
    /// Units of a currency or coin per euro, from crypto prices first and ECB rates otherwise.
    private struct Book {
        let rates: CurrencyRates?
        let crypto: CryptoPrices?

        func perEuro(_ code: String) -> Double? {
            if let price = crypto?.euros[code] { return 1 / price }
            if code == "EUR" { return 1 }
            return rates?.rate(code)
        }
    }

    private static let symbols: [Character: String] = ["$": "USD", "€": "EUR", "£": "GBP", "¥": "JPY", "₹": "INR", "₩": "KRW", "₺": "TRY"]
    private static let names: [String: String] = [
        "dollar": "USD", "dollars": "USD", "euro": "EUR", "euros": "EUR", "pound": "GBP", "pounds": "GBP", "quid": "GBP",
        "yen": "JPY", "franc": "CHF", "francs": "CHF", "yuan": "CNY", "rmb": "CNY", "renminbi": "CNY",
        "rupee": "INR", "rupees": "INR", "won": "KRW", "krona": "SEK", "kronor": "SEK", "zloty": "PLN", "lira": "TRY"
    ]
    private static let pattern = try! NSRegularExpression(pattern: #"^(.+?)\s+(?:in|to|as)\s+(.+)$"#)

    public static func evaluate(_ text: String, rates: CurrencyRates? = CurrencyRates.current, crypto: CryptoPrices? = CryptoPrices.current,
                                now: Date = Date(), zone: TimeZone = .current, locale: Locale = .current) -> CalculationAnswer? {
        let book = Book(rates: rates, crypto: crypto)
        guard rates != nil || crypto != nil, let (amount, from, to) = parse(text, locale: locale, known: book),
              let fromRate = book.perEuro(from), let toRate = book.perEuro(to) else { return nil }
        let value = amount / fromRate * toRate
        let coins = CryptoPrices.codes
        let tag: String
        if coins.contains(from) || coins.contains(to), let crypto {
            tag = cryptoTag(crypto.fetchedAt, now: now, zone: zone, locale: locale)
        } else if let rates {
            tag = dateTag(rates.date, now: now, locale: locale)
        } else {
            return nil
        }
        let input = text.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
        let result = money(value, to, locale: locale)
        let unit = rate(toRate / fromRate, locale: locale)
        let places = coins.contains(to) ? 1e8 : 100
        let swap = "\(Calculator.format((value * places).rounded() / places, locale: locale)) \(to) in \(from)"
        return CalculationAnswer(input: input, inputDetail: "1 \(from) = \(unit) \(to)", result: result,
                                 resultDetail: tag, copyText: result, swapQuery: swap)
    }

    /// Whether a conversion names a coin, so the app fetches crypto prices only for those.
    public static func involvesCrypto(_ text: String, locale: Locale = .current) -> Bool {
        guard let (_, from, to) = parse(text, locale: locale, known: nil) else { return false }
        return CryptoPrices.codes.contains(from) || CryptoPrices.codes.contains(to)
    }

    /// Recognizes a currency conversion's shape without rates, so the app can fetch them on
    /// first use and never otherwise.
    public static func looksLikeConversion(_ text: String, locale: Locale = .current) -> Bool {
        parse(text, locale: locale, known: nil) != nil
    }

    private static func parse(_ text: String, locale: Locale, known: Book?) -> (Double, String, String)? {
        let query = text.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
        guard query.utf8.count <= 64, let match = pattern.firstMatch(in: query, range: NSRange(query.startIndex..., in: query)),
              let left = Range(match.range(at: 1), in: query), let right = Range(match.range(at: 2), in: query),
              let to = currency(String(query[right]), known: known),
              let (amount, from) = money(String(query[left]), locale: locale, known: known), from != to else { return nil }
        return (amount, from, to)
    }

    /// "100 usd", "usd 100", "$100", "100$", "USD1K", "20 pounds".
    private static func money(_ text: String, locale: Locale, known: Book?) -> (Double, String)? {
        var rest = Substring(text)
        var code: String?
        if let first = rest.first, let symbol = symbols[first] { code = symbol; rest = rest.dropFirst() }
        else if let last = rest.last, let symbol = symbols[last] { code = symbol; rest = rest.dropLast() }
        else if rest.count > 3, let prefix = currency(String(rest.prefix(3)), known: known),
                rest.dropFirst(3).first.map({ $0.isNumber || $0 == " " }) == true {
            code = prefix; rest = rest.dropFirst(3)
        } else if let space = rest.lastIndex(of: " "), let suffix = currency(String(rest[rest.index(after: space)...]), known: known) {
            code = suffix; rest = rest[..<space]
        }
        guard let code, let amount = NumberLiteral.parse(rest.trimmingCharacters(in: .whitespaces), locale: locale), amount >= 0 else { return nil }
        return (amount, code)
    }

    /// An ISO code, coin ticker, symbol or name. Without rates, any ISO code or supported coin
    /// counts, since the feeds' lists are not known yet.
    private static func currency(_ text: String, known: Book?) -> String? {
        let word = text.trimmingCharacters(in: .whitespaces)
        if word.count == 1, let symbol = word.first.flatMap({ symbols[$0] }) { return symbol }
        if let name = names[word.lowercased()] ?? CryptoPrices.names[word.lowercased()] { return name }
        let code = word.uppercased()
        guard (3...4).contains(code.count), code.allSatisfy({ $0.isASCII && $0.isLetter }) else { return nil }
        if let known { return known.perEuro(code) == nil ? nil : code }
        return isoCodes.contains(code) || CryptoPrices.codes.contains(code) ? code : nil
    }

    private static let isoCodes = Set(Locale.Currency.isoCurrencies.map(\.identifier))

    /// Locale currency format, with the formatter's non-breaking spaces made ordinary so a pasted
    /// answer behaves like typed text. Coins show up to eight decimals and their ticker.
    private static func money(_ value: Double, _ code: String, locale: Locale) -> String {
        let formatter = NumberFormatter()
        formatter.locale = locale
        if CryptoPrices.codes.contains(code) {
            formatter.numberStyle = .decimal
            formatter.maximumFractionDigits = value >= 1 ? 4 : 8
            return (formatter.string(from: NSNumber(value: value)) ?? "\(value)") + " " + code
        }
        formatter.numberStyle = .currency
        formatter.currencyCode = code
        let text = formatter.string(from: NSNumber(value: value)) ?? "\(value) \(code)"
        return text.replacingOccurrences(of: "\u{00A0}", with: " ").replacingOccurrences(of: "\u{202F}", with: " ")
    }

    private static func rate(_ value: Double, locale: Locale) -> String {
        let formatter = NumberFormatter()
        formatter.locale = locale
        formatter.numberStyle = .decimal
        formatter.maximumSignificantDigits = 5
        formatter.usesSignificantDigits = true
        return formatter.string(from: NSNumber(value: value)) ?? String(value)
    }

    /// "CoinGecko · 2:15 PM", with the date once it is not today and "Old" after an hour.
    private static func cryptoTag(_ fetched: Date, now: Date, zone: TimeZone, locale: Locale) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.timeZone = zone
        formatter.setLocalizedDateFormatFromTemplate(calendar.isDate(fetched, inSameDayAs: now) ? "jmm" : "MMMdjmm")
        let old = now.timeIntervalSince(fetched) > 3600
        let time = formatter.string(from: fetched).replacingOccurrences(of: "\u{202F}", with: " ").replacingOccurrences(of: "\u{00A0}", with: " ")
        return (old ? "Old CoinGecko prices · " : "CoinGecko · ") + time
    }

    /// "ECB rates · Oct 5", with "Old" when more than a week behind.
    private static func dateTag(_ date: String, now: Date, locale: Locale) -> String {
        let parser = DateFormatter()
        parser.locale = Locale(identifier: "en_US_POSIX")
        parser.timeZone = TimeZone(identifier: "Europe/Berlin")
        parser.dateFormat = "yyyy-MM-dd"
        guard let day = parser.date(from: date) else { return "ECB rates" }
        let display = DateFormatter()
        display.locale = locale
        display.timeZone = parser.timeZone
        display.setLocalizedDateFormatFromTemplate("MMMd")
        let old = now.timeIntervalSince(day) > 8 * 86_400
        return (old ? "Old ECB rates · " : "ECB rates · ") + display.string(from: day)
    }
}
