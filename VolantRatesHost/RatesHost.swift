import Foundation
import VolantCore

/// Fetches the ECB daily reference feed and CoinGecko prices for a fixed coin list, and nothing
/// else: the URLs are fixed, requests carry no cookies or cache, redirects are refused, and a
/// response is returned only when it parses. The owner's CoinGecko key is the only input, sent
/// only to CoinGecko. The calling app has no network access of its own.
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

    func fetchCrypto(key: String, reply: @escaping (Data?, String?) -> Void) {
        guard CryptoPrices.validKey(key) else { return reply(nil, "Enter a valid CoinGecko key.") }
        var request = URLRequest(url: CryptoPrices.request)
        request.setValue(key, forHTTPHeaderField: CryptoPrices.keyHeader)
        session.dataTask(with: request) { data, response, _ in
            let status = (response as? HTTPURLResponse)?.statusCode
            guard status == 200, let data, data.count <= CryptoPrices.maximumBytes, CryptoPrices.parse(data, at: Date()) != nil else {
                reply(nil, status == 401 || status == 403 ? "CoinGecko didn’t accept the key." : "Couldn’t get crypto prices.")
                return
            }
            reply(data, nil)
        }.resume()
    }

    /// Refusing redirects keeps every request on the fixed ECB and CoinGecko URLs.
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(nil)
    }

    func stop() { session.invalidateAndCancel() }
}
