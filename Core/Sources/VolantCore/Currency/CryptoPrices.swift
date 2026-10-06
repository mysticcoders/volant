import Foundation

/// Euro prices of major cryptocurrencies from CoinGecko's simple price API, fetched with the
/// owner's own free Demo key. The request names a fixed list of coins, so nothing typed in Volant
/// is sent; the key is the only input. CoinGecko's free tier requires attribution, which the card
/// tag and Settings give.
public struct CryptoPrices: Codable, Equatable {
    /// CoinGecko id, ticker, and the names people type.
    public static let coins: [(id: String, code: String, names: [String])] = [
        ("bitcoin", "BTC", ["bitcoin", "bitcoins"]), ("ethereum", "ETH", ["ethereum", "ether"]), ("solana", "SOL", ["solana"]),
        ("ripple", "XRP", ["ripple"]), ("binancecoin", "BNB", []), ("cardano", "ADA", ["cardano"]),
        ("dogecoin", "DOGE", ["dogecoin"]), ("tether", "USDT", ["tether"]), ("usd-coin", "USDC", []),
        ("litecoin", "LTC", ["litecoin"]), ("polkadot", "DOT", ["polkadot"]), ("tron", "TRX", ["tron"])
    ]
    public static let codes = Set(coins.map(\.code))
    public static let names: [String: String] = Dictionary(uniqueKeysWithValues: coins.flatMap { coin in coin.names.map { ($0, coin.code) } })

    public static var request: URL {
        var parts = URLComponents(string: "https://api.coingecko.com/api/v3/simple/price")!
        parts.queryItems = [URLQueryItem(name: "ids", value: coins.map(\.id).joined(separator: ",")), URLQueryItem(name: "vs_currencies", value: "eur")]
        return parts.url!
    }
    public static let keyHeader = "x-cg-demo-api-key"
    /// The response for a dozen coins is under 1 KB.
    public static let maximumBytes = 16_384

    public let fetchedAt: Date
    /// Euros per one unit of each coin, keyed by ticker.
    public let euros: [String: Double]

    public init(fetchedAt: Date, euros: [String: Double]) {
        self.fetchedAt = fetchedAt
        self.euros = euros
    }

    /// Installed by the app once prices are fetched or loaded; nil without a key or before first use.
    public static var current: CryptoPrices?

    /// Parses `{"bitcoin": {"eur": 58123.4}, ...}`, requiring positive prices for at least half the
    /// coins, so an error body or a partial outage is rejected.
    public static func parse(_ data: Data, at time: Date) -> CryptoPrices? {
        guard data.count <= maximumBytes, let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { return nil }
        var euros: [String: Double] = [:]
        for coin in coins {
            if let price = ((object[coin.id] as? [String: Any])?["eur"] as? NSNumber)?.doubleValue, price > 0, price.isFinite {
                euros[coin.code] = price
            }
        }
        return euros.count * 2 >= coins.count ? CryptoPrices(fetchedAt: time, euros: euros) : nil
    }

    /// CoinGecko keys are short tokens of letters, digits, dashes and underscores.
    public static func validKey(_ key: String) -> Bool {
        (8...128).contains(key.count) && key.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-" || $0 == "_") }
    }
}
