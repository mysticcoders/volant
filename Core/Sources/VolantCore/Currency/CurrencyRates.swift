import Foundation

/// The rates-only XPC helper's interface: it fetches the ECB daily reference feed and replies
/// with the validated XML, or an error message. It takes no input, so no query ever leaves Volant.
@objc public protocol VolantRatesHostProtocol {
    func fetchRates(reply: @escaping (Data?, String?) -> Void)
}

/// European Central Bank daily reference rates: units of each currency per euro, for one
/// business day. Parsed from the public eurofxref feed; nothing else about the response is used.
public struct CurrencyRates: Codable, Equatable {
    public static let feed = URL(string: "https://www.ecb.europa.eu/stats/eurofxref/eurofxref-daily.xml")!
    /// The feed is about 1.5 KB; anything far larger is not the feed.
    public static let maximumBytes = 65_536

    /// The ECB business day the rates are for, as yyyy-MM-dd.
    public let date: String
    public let perEuro: [String: Double]

    public init(date: String, perEuro: [String: Double]) {
        self.date = date
        self.perEuro = perEuro
    }

    /// Installed by the app once rates are loaded or fetched; nil until the owner first converts
    /// currency.
    public static var current: CurrencyRates?

    /// Units of `code` per euro; the euro itself is 1.
    public func rate(_ code: String) -> Double? {
        code == "EUR" ? 1 : perEuro[code]
    }

    /// Parses the ECB feed. Requires a date and at least a handful of positive rates with
    /// three-letter codes, so an error page or a truncated response is rejected.
    public static func parse(_ data: Data) -> CurrencyRates? {
        guard data.count <= maximumBytes else { return nil }
        let reader = Reader()
        let parser = XMLParser(data: data)
        parser.delegate = reader
        guard parser.parse(), let date = reader.date, reader.rates.count >= 5,
              date.range(of: #"^\d{4}-\d{2}-\d{2}$"#, options: .regularExpression) != nil else { return nil }
        return CurrencyRates(date: date, perEuro: reader.rates)
    }

    private final class Reader: NSObject, XMLParserDelegate {
        var date: String?
        var rates: [String: Double] = [:]

        func parser(_ parser: XMLParser, didStartElement name: String, namespaceURI: String?, qualifiedName: String?,
                    attributes: [String: String] = [:]) {
            guard name == "Cube" else { return }
            if let time = attributes["time"] { date = time }
            if let code = attributes["currency"], let text = attributes["rate"], let rate = Double(text),
               rate > 0, code.count == 3, code.allSatisfy({ $0.isASCII && $0.isUppercase }) {
                rates[code] = rate
            }
        }
    }
}
