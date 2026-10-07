import Foundation

/// Daily rates for about 160 currencies from ExchangeRate-API's open access endpoint, used only for
/// currencies the ECB reference feed lacks (AED, SAR, ARS, TWD, VND, NGN and so on). The request
/// is a fixed, euro-based URL with no key and nothing typed in Volant. ExchangeRate-API allows
/// commercial use with attribution ("Rates By Exchange Rate API" linking to its site), which the
/// card tag and Settings → Acknowledgements give; the data may be cached but not redistributed.
public struct WorldRates: Codable, Equatable {
    public static let feed = URL(string: "https://open.er-api.com/v6/latest/EUR")!
    public static let attribution = URL(string: "https://www.exchangerate-api.com")!
    /// The response for ~166 currencies is about 3 KB.
    public static let maximumBytes = 32_768

    /// When the provider last updated the rates.
    public let updated: Date
    public let perEuro: [String: Double]

    public init(updated: Date, perEuro: [String: Double]) {
        self.updated = updated
        self.perEuro = perEuro
    }

    /// Installed by the app once rates are loaded or fetched; nil until the owner first converts a
    /// currency the ECB does not cover.
    public static var current: WorldRates?

    /// Units of `code` per euro; the euro itself is 1.
    public func rate(_ code: String) -> Double? {
        code == "EUR" ? 1 : perEuro[code]
    }

    /// Parses `{"result": "success", "base_code": "EUR", "time_last_update_unix": …, "rates": {…}}`.
    /// Requires a euro base, an update time and at least fifty positive rates with three-letter
    /// codes, so an error body, another base or a truncated response is rejected.
    public static func parse(_ data: Data) -> WorldRates? {
        guard data.count <= maximumBytes, let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              object["result"] as? String == "success", object["base_code"] as? String == "EUR",
              let time = (object["time_last_update_unix"] as? NSNumber)?.doubleValue, time > 0,
              let rates = object["rates"] as? [String: Any] else { return nil }
        var perEuro: [String: Double] = [:]
        for (code, value) in rates where code != "EUR" && code.count == 3 && code.allSatisfy({ $0.isASCII && $0.isUppercase }) {
            if let rate = (value as? NSNumber)?.doubleValue, rate > 0, rate.isFinite { perEuro[code] = rate }
        }
        return perEuro.count >= 50 ? WorldRates(updated: Date(timeIntervalSince1970: time), perEuro: perEuro) : nil
    }
}
