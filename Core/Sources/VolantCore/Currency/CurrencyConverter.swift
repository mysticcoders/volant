import Foundation

/// Currency conversion with ECB reference rates: "100 usd in eur", "$100 in gbp", "€50 to yen",
/// "USD1K in CHF", "20 pounds in euros". Cross rates go through the euro. The card tags the rate
/// date, so cached rates are never mistaken for live prices; without rates there is no answer.
///
/// Symbols and names map to one currency each ($ and dollars are US dollars, ¥ and yen are
/// Japanese yen); other dollars and pesos need their ISO code. "pounds" is currency only when the
/// other side is a currency, so "5 pounds in kg" stays a weight.
///
/// A rate per unit of time converts the amount and keeps the unit: "8 dollars/hour in gbp", "$50 per
/// hour in eur", "€90 a day to usd". The target may repeat the same unit ("in eur/hour") but not
/// change it, since a day of work and a calendar day differ.
///
/// With `CryptoPrices` from CoinGecko, major coins convert too ("0.5 btc in usd",
/// "100 eur in eth"), through their euro price; those cards tag CoinGecko and the fetch time.
///
/// Currencies the ECB does not publish ("100 aed in usd", "5000 twd to vnd") use `WorldRates`
/// from ExchangeRate-API. Both sides of one conversion always come from the same source: ECB
/// when it covers every fiat currency named, otherwise ExchangeRate-API for all of them, so a
/// cross rate never mixes two providers' euro rates. Those cards tag ExchangeRate-API's date.
public enum CurrencyConverter {
    private enum Basis { case ecb, world }

    /// Units of a currency or coin per euro, from crypto prices first, then from whichever fiat
    /// source covers every fiat currency in the conversion.
    private struct Book {
        let rates: CurrencyRates?
        let world: WorldRates?
        let crypto: CryptoPrices?

        /// Whether any source knows the code, for reading a word as a currency.
        func knows(_ code: String) -> Bool {
            code == "EUR" || crypto?.euros[code] != nil || rates?.rate(code) != nil || world?.rate(code) != nil
        }

        /// ECB when it has every fiat code, ExchangeRate-API when it does, else nothing. A
        /// conversion between coins (and the euro) needs neither.
        func basis(_ codes: [String]) -> Basis? {
            let fiat = codes.filter { crypto?.euros[$0] == nil && $0 != "EUR" }
            if fiat.allSatisfy({ rates?.rate($0) != nil }) { return .ecb }
            if let world, fiat.allSatisfy({ world.rate($0) != nil }) { return .world }
            return nil
        }

        func perEuro(_ code: String, _ basis: Basis) -> Double? {
            if let price = crypto?.euros[code] { return 1 / price }
            if code == "EUR" { return 1 }
            return basis == .ecb ? rates?.rate(code) : world?.rate(code)
        }
    }

    static let symbols: [Character: String] = [
        "$": "USD", "€": "EUR", "£": "GBP", "¥": "JPY", "₹": "INR", "₩": "KRW", "₺": "TRY",
        "₦": "NGN", "₴": "UAH", "₫": "VND", "₪": "ILS", "₱": "PHP", "₸": "KZT", "₾": "GEL", "₽": "RUB", "₵": "GHS"
    ]
    /// Names that mean one currency. Shared names such as dirham, riyal, dinar, peso and shilling
    /// are left out, so those need their ISO code.
    static let names: [String: String] = [
        "dollar": "USD", "dollars": "USD", "euro": "EUR", "euros": "EUR", "pound": "GBP", "pounds": "GBP", "quid": "GBP",
        "yen": "JPY", "franc": "CHF", "francs": "CHF", "yuan": "CNY", "rmb": "CNY", "renminbi": "CNY",
        "rupee": "INR", "rupees": "INR", "won": "KRW", "krona": "SEK", "kronor": "SEK", "zloty": "PLN", "lira": "TRY",
        "baht": "THB", "rand": "ZAR", "shekel": "ILS", "shekels": "ILS", "forint": "HUF", "ringgit": "MYR", "rupiah": "IDR",
        "naira": "NGN", "hryvnia": "UAH", "hryvnias": "UAH", "dong": "VND", "taka": "BDT", "cedi": "GHS", "cedis": "GHS",
        "lari": "GEL", "tenge": "KZT", "ruble": "RUB", "rubles": "RUB", "rouble": "RUB", "roubles": "RUB"
    ]
    private static let pattern = try! NSRegularExpression(pattern: #"^(.+?)\s+(?:in|to|as)\s+(.+)$"#)
    private static let ratePattern = try! NSRegularExpression(pattern:
        #"^(.+?)\s*(?:/|\s+per\s+|\s+an?\s+)(hours?|hrs?|h|minutes?|mins?|days?|weeks?|wks?|months?|mo|years?|yrs?)$"#)
    private static let timeUnits: [String: String] = ["h": "hour", "hr": "hour", "min": "minute", "wk": "week", "mo": "month", "yr": "year"]

    public static func evaluate(_ text: String, rates: CurrencyRates? = CurrencyRates.current, world: WorldRates? = WorldRates.current,
                                crypto: CryptoPrices? = CryptoPrices.current, now: Date = Date(), zone: TimeZone = .current,
                                locale: Locale = .current) -> CalculationAnswer? {
        let book = Book(rates: rates, world: world, crypto: crypto)
        guard rates != nil || world != nil || crypto != nil, let (amount, from, to, per) = parse(text, locale: locale, known: book),
              let basis = book.basis([from, to]), let fromRate = book.perEuro(from, basis),
              let toRate = book.perEuro(to, basis) else { return nil }
        let value = amount / fromRate * toRate
        let coins = CryptoPrices.codes
        let tag: String
        if coins.contains(from) || coins.contains(to), let crypto {
            tag = cryptoTag(crypto.fetchedAt, now: now, zone: zone, locale: locale)
        } else if basis == .world, let world {
            tag = worldTag(world.updated, now: now, zone: zone, locale: locale)
        } else if let rates {
            tag = dateTag(rates.date, now: now, locale: locale)
        } else {
            return nil
        }
        let input = text.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
        let result = money(value, to, locale: locale) + (per.map { " per \($0)" } ?? "")
        let unit = rate(toRate / fromRate, locale: locale)
        let places = coins.contains(to) ? 1e8 : 100
        let swap = "\(Calculator.format((value * places).rounded() / places, locale: locale)) \(to)\(per.map { "/\($0)" } ?? "") in \(from)"
        return CalculationAnswer(input: input, inputDetail: "1 \(from) = \(unit) \(to)", result: result,
                                 resultDetail: tag, copyText: result, swapQuery: swap)
    }

    /// Whether a conversion names a coin, so the app fetches crypto prices only for those.
    public static func involvesCrypto(_ text: String, locale: Locale = .current) -> Bool {
        guard let (_, from, to, _) = parse(text, locale: locale, known: nil) else { return false }
        return CryptoPrices.codes.contains(from) || CryptoPrices.codes.contains(to)
    }

    /// Recognizes a currency conversion's shape without rates, so the app can fetch them on
    /// first use and never otherwise.
    public static func looksLikeConversion(_ text: String, locale: Locale = .current) -> Bool {
        parse(text, locale: locale, known: nil) != nil
    }

    /// Whether a conversion names a fiat currency the ECB does not publish, so the app fetches
    /// ExchangeRate-API's rates only for those. Before ECB rates are loaded, its usual list decides.
    public static func needsWorldRates(_ text: String, locale: Locale = .current) -> Bool {
        guard let (_, from, to, _) = parse(text, locale: locale, known: nil) else { return false }
        let ecb = CurrencyRates.current.map { Set($0.perEuro.keys) } ?? CurrencyRates.referenceCodes
        return [from, to].contains { $0 != "EUR" && !CryptoPrices.codes.contains($0) && !ecb.contains($0) }
    }

    private static func parse(_ text: String, locale: Locale, known: Book?) -> (Double, String, String, String?)? {
        let query = text.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
        guard query.utf8.count <= 64, let match = pattern.firstMatch(in: query, range: NSRange(query.startIndex..., in: query)),
              let left = Range(match.range(at: 1), in: query), let right = Range(match.range(at: 2), in: query) else { return nil }
        let (source, per) = perTime(String(query[left]))
        let (target, targetPer) = perTime(String(query[right]))
        guard targetPer == nil || targetPer == per, let to = currency(target, known: known),
              let (amount, from) = money(source, locale: locale, known: known), from != to else { return nil }
        return (amount, from, to, per)
    }

    /// Splits a rate's unit of time from its amount: "8 dollars/hour" gives "8 dollars" and
    /// "hour". Text without one comes back whole.
    private static func perTime(_ text: String) -> (String, String?) {
        guard let match = ratePattern.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let body = Range(match.range(at: 1), in: text), let unit = Range(match.range(at: 2), in: text) else { return (text, nil) }
        var name = text[unit].lowercased()
        if name.count > 2, name.hasSuffix("s") { name.removeLast() }
        return (String(text[body]), timeUnits[name] ?? name)
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
        if let known { return known.knows(code) ? code : nil }
        return isoCodes.contains(code) || CryptoPrices.codes.contains(code) ? code : nil
    }

    private static let isoCodes = Set(Locale.Currency.isoCurrencies.map(\.identifier))

    /// Locale currency format, with the formatter's non-breaking spaces made ordinary so a pasted
    /// answer behaves like typed text. Coins show up to eight decimals and their ticker.
    static func money(_ value: Double, _ code: String, locale: Locale) -> String {
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

    /// "Rates By Exchange Rate API · Oct 6", the provider's required attribution, with "Old" once
    /// the daily rates are more than three days behind.
    private static func worldTag(_ updated: Date, now: Date, zone: TimeZone, locale: Locale) -> String {
        let display = DateFormatter()
        display.locale = locale
        display.timeZone = zone
        display.setLocalizedDateFormatFromTemplate("MMMd")
        let old = now.timeIntervalSince(updated) > 3 * 86_400
        return (old ? "Old rates by Exchange Rate API · " : "Rates By Exchange Rate API · ") + display.string(from: updated)
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
