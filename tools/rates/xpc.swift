import Foundation
import VolantCore

/// Asks the embedded rates helper for the ECB feed once, and for CoinGecko prices when
/// VOLANT_COINGECKO_KEY is set, and reports what came back. The key is never printed.
let connection = NSXPCConnection(serviceName: "com.mysticcoders.volant.RatesHost")
connection.remoteObjectInterface = NSXPCInterface(with: VolantRatesHostProtocol.self)
connection.resume()
let proxy = connection.remoteObjectProxyWithErrorHandler { error in
    print("Rates XPC failed: \(error.localizedDescription)"); exit(1)
} as! VolantRatesHostProtocol
proxy.fetchRates { data, error in
    guard let data, let rates = CurrencyRates.parse(data) else { print("Rates fetch failed: \(error ?? "invalid feed")"); exit(1) }
    print("Rates XPC: \(rates.perEuro.count) currencies for \(rates.date); \(data.count) bytes")
    guard let key = ProcessInfo.processInfo.environment["VOLANT_COINGECKO_KEY"], !key.isEmpty else {
        print("Crypto XPC: skipped (no VOLANT_COINGECKO_KEY)"); exit(0)
    }
    proxy.fetchCrypto(key: key) { data, error in
        guard let data, let prices = CryptoPrices.parse(data, at: Date()) else { print("Crypto fetch failed: \(error ?? "invalid response")"); exit(1) }
        print("Crypto XPC: \(prices.euros.count) coins; \(data.count) bytes")
        exit(0)
    }
}
DispatchQueue.main.asyncAfter(deadline: .now() + 60) { print("Rates XPC timed out"); exit(1) }
dispatchMain()
