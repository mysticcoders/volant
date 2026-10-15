import Foundation
import VolantCore

/// Sends a network extension's requests through the sandboxed VolantFetchHost, one short-lived
/// connection per request. Volant itself has no network access. Each request completes exactly once: with
/// the helper's reply, a connection failure, or a timeout. A failed request becomes status 0 with an empty
/// body so the extension can still render the ones that did load. Header values, which carry the owner's
/// tokens, go only to the helper and are never logged.
enum ExtensionFetcher {
    static func fetch(_ requests: [ExtensionRequest], hosts: [String], completion: @escaping ([ExtensionNetwork.Response]) -> Void) {
        var responses = [ExtensionNetwork.Response?](repeating: nil, count: requests.count)
        let group = DispatchGroup()
        for (index, request) in requests.enumerated() {
            group.enter()
            fetchOne(request, hosts: hosts) { response in
                responses[index] = response
                group.leave()
            }
        }
        group.notify(queue: .main) { completion(responses.compactMap { $0 }) }
    }

    private static func fetchOne(_ request: ExtensionRequest, hosts: [String], completion: @escaping (ExtensionNetwork.Response) -> Void) {
        call(timeout: 35, { proxy, reply in
            proxy.request(url: request.url.absoluteString, method: request.method, body: request.body, headers: request.headers,
                          allowedHosts: hosts, maximumBytes: ExtensionNetwork.maximumResponseBytes, reply: reply)
        }) { data, status, error in
            let body = error == nil ? data : nil
            let text = body.flatMap { String(data: $0, encoding: .utf8) }
            completion(ExtensionNetwork.Response(url: request.url.absoluteString, status: body == nil || text == nil ? 0 : status, body: text ?? ""))
        }
    }

    /// Reads one extension catalog file through the helper's fixed-location method. Anything other than
    /// a complete 200 response is an error; the caller verifies signatures and hashes.
    static func catalogFile(_ path: String, maximumBytes: Int, completion: @escaping (Result<Data, Error>) -> Void) {
        call(timeout: 45, { proxy, reply in
            proxy.fetchCatalogFile(path: path, maximumBytes: maximumBytes, reply: reply)
        }) { data, status, error in
            if let data, error == nil, status == 200 { completion(.success(data)); return }
            let detail = error ?? (status == 0 ? "The fetch helper did not answer." : "The server answered \(status).")
            completion(.failure(ExtensionCatalogError.unavailable(detail)))
        }
    }

    /// One short-lived helper connection that completes exactly once, on the main queue: with the
    /// helper's reply, or with no data and status 0 after a connection failure or the timeout.
    private static func call(timeout: TimeInterval, _ request: (VolantFetchHostProtocol, @escaping (Data?, Int, String?) -> Void) -> Void,
                             completion: @escaping (Data?, Int, String?) -> Void) {
        let connection = NSXPCConnection(serviceName: "com.mysticcoders.volant.FetchHost")
        connection.remoteObjectInterface = NSXPCInterface(with: VolantFetchHostProtocol.self)
        let lock = NSLock()
        var finished = false
        let finish: (Data?, Int, String?) -> Void = { data, status, error in
            lock.lock(); defer { lock.unlock() }
            guard !finished else { return }
            finished = true
            connection.invalidate()
            DispatchQueue.main.async { completion(data, status, error) }
        }
        connection.invalidationHandler = { finish(nil, 0, nil) }
        connection.interruptionHandler = { finish(nil, 0, nil) }
        connection.resume()
        DispatchQueue.main.asyncAfter(deadline: .now() + timeout) { finish(nil, 0, "The request timed out.") }
        guard let proxy = connection.remoteObjectProxyWithErrorHandler({ _ in finish(nil, 0, nil) }) as? VolantFetchHostProtocol else {
            finish(nil, 0, nil); return
        }
        request(proxy, finish)
    }
}
