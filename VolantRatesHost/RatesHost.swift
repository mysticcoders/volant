import Foundation
import VolantCore

/// Fetches the ECB daily reference feed, ExchangeRate-API's daily rates for the currencies ECB
/// lacks, and CoinGecko prices for a fixed coin list, and nothing else: the URLs are fixed, requests carry no cookies or cache, redirects are refused, and a
/// response is returned only when it parses. The owner's optional CoinGecko key is the only input,
/// sent only to CoinGecko; without one, prices come from CoinGecko's keyless public API. The calling app has no network access of its own.
final class RatesHost: NSObject, VolantRatesHostProtocol, URLSessionTaskDelegate {
    private lazy var session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 15
        configuration.timeoutIntervalForResource = 30
        configuration.httpCookieStorage = nil
        configuration.urlCache = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        return URLSession(configuration: configuration, delegate: self, delegateQueue: nil)
    }()

    func fetchRates(reply: @escaping (Data?, String?) -> Void) {
        session.dataTask(with: URLRequest(url: CurrencyRates.feed)) { data, response, _ in
            guard let http = response as? HTTPURLResponse, http.statusCode == 200, let data,
                  data.count <= CurrencyRates.maximumBytes, CurrencyRates.parse(data) != nil else {
                reply(nil, "Couldn’t get exchange rates.")
                return
            }
            reply(data, nil)
        }.resume()
    }

    /// Fetches ExchangeRate-API's euro-based open access rates. The app's hourly retry already
    /// outlasts the provider's twenty-minute limit after a 429, so every failure replies alike.
    func fetchWorldRates(reply: @escaping (Data?, String?) -> Void) {
        session.dataTask(with: URLRequest(url: WorldRates.feed)) { data, response, _ in
            guard (response as? HTTPURLResponse)?.statusCode == 200, let data, data.count <= WorldRates.maximumBytes,
                  WorldRates.parse(data) != nil else {
                reply(nil, "Couldn’t get exchange rates.")
                return
            }
            reply(data, nil)
        }.resume()
    }

    /// Fetches the fixed coin list, sending the key header only when the owner saved a key. A 429
    /// replies with `CryptoPrices.busyMessage` so the app backs off longer than for other failures.
    func fetchCrypto(key: String?, reply: @escaping (Data?, String?) -> Void) {
        var request = URLRequest(url: CryptoPrices.request)
        if let key {
            guard CryptoPrices.validKey(key) else { return reply(nil, "Enter a valid CoinGecko key.") }
            request.setValue(key, forHTTPHeaderField: CryptoPrices.keyHeader)
        }
        session.dataTask(with: request) { data, response, _ in
            let status = (response as? HTTPURLResponse)?.statusCode
            guard status == 200, let data, data.count <= CryptoPrices.maximumBytes, CryptoPrices.parse(data, at: Date()) != nil else {
                switch status {
                case 401, 403: reply(nil, key == nil ? "Couldn’t get crypto prices." : "CoinGecko didn’t accept the key.")
                case 429: reply(nil, CryptoPrices.busyMessage)
                default: reply(nil, "Couldn’t get crypto prices.")
                }
                return
            }
            reply(data, nil)
        }.resume()
    }

    /// Refusing redirects keeps every request on the fixed ECB, ExchangeRate-API and CoinGecko URLs.
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(nil)
    }

    func stop() { session.invalidateAndCancel() }
}
