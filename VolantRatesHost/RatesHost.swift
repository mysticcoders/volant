import Foundation
import VolantCore

/// Fetches the ECB daily reference feed, and nothing else: the URL is fixed, requests carry no
/// cookies or cache, redirects are refused, and a response is returned only when it parses as the
/// feed. The calling app has no network access of its own.
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

    /// Refusing redirects keeps every request on the ECB feed.
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(nil)
    }

    func stop() { session.invalidateAndCancel() }
}
