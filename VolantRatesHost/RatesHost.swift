import Foundation
import VolantCore

/// Reads only the fixed currency feeds. Bodies are bounded while receiving, redirects are refused,
/// and only parsed responses cross XPC. The optional key is sent only to CoinGecko.
final class RatesHost: NSObject, VolantRatesHostProtocol, URLSessionDataDelegate {
    private struct Pending {
        var data = Data()
        let limit: Int
        let valid: (Data) -> Bool
        let failure: (Int) -> String
        let reply: (Data?, String?) -> Void
    }
    private let lock = NSLock()
    private var pending: [Int: Pending] = [:]
    private var session: URLSession!

    init(configuration: URLSessionConfiguration = .ephemeral) {
        super.init()
        configuration.timeoutIntervalForRequest = 15
        configuration.timeoutIntervalForResource = 30
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.urlCredentialStorage = nil
        configuration.urlCache = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        session = URLSession(configuration: configuration, delegate: self, delegateQueue: nil)
    }

    func fetchRates(reply: @escaping (Data?, String?) -> Void) {
        start(URLRequest(url: CurrencyRates.feed), limit: CurrencyRates.maximumBytes,
              valid: { CurrencyRates.parse($0) != nil }, failure: { _ in "Couldn’t get exchange rates." }, reply: reply)
    }

    func fetchWorldRates(reply: @escaping (Data?, String?) -> Void) {
        start(URLRequest(url: WorldRates.feed), limit: WorldRates.maximumBytes,
              valid: { WorldRates.parse($0) != nil }, failure: { _ in "Couldn’t get exchange rates." }, reply: reply)
    }

    /// A 429 keeps the app's longer backoff; a rejected saved key keeps its specific explanation.
    func fetchCrypto(key: String?, reply: @escaping (Data?, String?) -> Void) {
        var request = URLRequest(url: CryptoPrices.request)
        if let key {
            guard CryptoPrices.validKey(key) else { return reply(nil, "Enter a valid CoinGecko key.") }
            request.setValue(key, forHTTPHeaderField: CryptoPrices.keyHeader)
        }
        start(request, limit: CryptoPrices.maximumBytes, valid: { CryptoPrices.parse($0, at: Date()) != nil }, failure: { status in
            switch status {
            case 401, 403: return key == nil ? "Couldn’t get crypto prices." : "CoinGecko didn’t accept the key."
            case 429: return CryptoPrices.busyMessage
            default: return "Couldn’t get crypto prices."
            }
        }, reply: reply)
    }

    private func start(_ request: URLRequest, limit: Int, valid: @escaping (Data) -> Bool,
                       failure: @escaping (Int) -> String, reply: @escaping (Data?, String?) -> Void) {
        let task = session.dataTask(with: request)
        lock.lock()
        pending[task.taskIdentifier] = Pending(limit: limit, valid: valid, failure: failure, reply: reply)
        lock.unlock()
        task.resume()
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse,
                    completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        lock.lock()
        guard let entry = pending[dataTask.taskIdentifier] else { lock.unlock(); completionHandler(.cancel); return }
        let rejected = status != 200 || response.expectedContentLength > Int64(entry.limit)
        if rejected { pending[dataTask.taskIdentifier] = nil }
        lock.unlock()
        completionHandler(rejected ? .cancel : .allow)
        if rejected { entry.reply(nil, entry.failure(status)) }
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        lock.lock()
        guard var entry = pending[dataTask.taskIdentifier] else { lock.unlock(); return }
        // Check before appending: neither a large chunk nor many small chunks may grow our buffer past the cap.
        if data.count > entry.limit - entry.data.count {
            pending[dataTask.taskIdentifier] = nil
            lock.unlock()
            dataTask.cancel()
            entry.reply(nil, entry.failure((dataTask.response as? HTTPURLResponse)?.statusCode ?? 0))
            return
        }
        entry.data.append(data)
        pending[dataTask.taskIdentifier] = entry
        lock.unlock()
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        lock.lock()
        let entry = pending.removeValue(forKey: task.taskIdentifier)
        lock.unlock()
        guard let entry else { return }
        let status = (task.response as? HTTPURLResponse)?.statusCode ?? 0
        guard error == nil, status == 200, entry.valid(entry.data) else { entry.reply(nil, entry.failure(status)); return }
        entry.reply(entry.data, nil)
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(nil)
    }

    func stop() { session.invalidateAndCancel() }
}
