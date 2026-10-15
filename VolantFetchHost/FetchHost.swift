import Foundation
import VolantCore

/// Fetches URLs that network extensions planned, on the owner's approved hosts only, and the files of
/// the signed extension catalog from its one fixed location. Volant and the
/// extension helper have no network access; this helper has nothing else. Every URL is checked again
/// here against the hosts Volant passed, redirects are refused so a response cannot move the request to
/// another host, no cookies or cache are used, and reading stops once the response passes the byte limit.
final class FetchHost: NSObject, VolantFetchHostProtocol, URLSessionDataDelegate {
    private struct Pending {
        var data = Data()
        let limit: Int
        let reply: (Data?, Int, String?) -> Void
    }
    private let lock = NSLock()
    private var pending: [Int: Pending] = [:]
    private lazy var session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 15
        configuration.timeoutIntervalForResource = 30
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.urlCache = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.httpAdditionalHeaders = ["User-Agent": "Volant extension fetch"]
        return URLSession(configuration: configuration, delegate: self, delegateQueue: nil)
    }()

    func request(url: String, method: String, body: Data?, headers: [String: String], allowedHosts: [String], maximumBytes: Int,
                 reply: @escaping (Data?, Int, String?) -> Void) {
        let hosts = Set(allowedHosts.filter(ExtensionNetwork.isValidHost))
        guard let target = ExtensionNetwork.permittedURL(url, hosts: hosts) else {
            reply(nil, 0, "This URL is not on a host the extension may reach."); return
        }
        guard ExtensionRequest.isAllowed(method: method, body: body, headers: headers) else {
            reply(nil, 0, "This request is not one an extension may send."); return
        }
        var request = URLRequest(url: target)
        request.httpMethod = method
        for (name, value) in headers { request.setValue(value, forHTTPHeaderField: name) }
        if let body {
            request.httpBody = body
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        start(request, limit: min(max(maximumBytes, 0), ExtensionNetwork.maximumResponseBytes), reply: reply)
    }

    /// Reads one file of the signed extension catalog. Only the index, its signature and package paths
    /// under the fixed catalog URL are accepted, so Volant cannot use this to reach any other host.
    /// Volant verifies the signature and hashes; this helper only bounds the download.
    func fetchCatalogFile(path: String, maximumBytes: Int, reply: @escaping (Data?, Int, String?) -> Void) {
        guard let target = ExtensionCatalog.url(for: path) else { reply(nil, 0, "This is not an extension catalog file."); return }
        start(URLRequest(url: target), limit: min(max(maximumBytes, 0), ExtensionCatalog.maximumModuleBytes), reply: reply)
    }

    private func start(_ request: URLRequest, limit: Int, reply: @escaping (Data?, Int, String?) -> Void) {
        let task = session.dataTask(with: request)
        lock.lock(); pending[task.taskIdentifier] = Pending(limit: limit, reply: reply); lock.unlock()
        task.resume()
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        lock.lock()
        guard var entry = pending[dataTask.taskIdentifier] else { lock.unlock(); return }
        entry.data.append(data)
        let over = entry.data.count > entry.limit
        if over { pending[dataTask.taskIdentifier] = nil } else { pending[dataTask.taskIdentifier] = entry }
        lock.unlock()
        if over {
            dataTask.cancel()
            entry.reply(nil, 0, "The response is larger than \(entry.limit / 1024) KB.")
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        lock.lock(); let entry = pending.removeValue(forKey: task.taskIdentifier); lock.unlock()
        guard let entry else { return }
        let status = (task.response as? HTTPURLResponse)?.statusCode ?? 0
        if let error { entry.reply(nil, status, error.localizedDescription) } else { entry.reply(entry.data, status, nil) }
    }

    /// Refusing redirects keeps every request on the URL the owner's approved host check passed.
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(nil)
    }

    func stop() { session.invalidateAndCancel() }
}
