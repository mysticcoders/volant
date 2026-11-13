import Foundation
import VolantCore

/// Sends a network extension's requests through the sandboxed VolantFetchHost, one short-lived
/// connection per request. Volant itself has no network access. Each request completes exactly once: with
/// the helper's reply, a connection failure, or a timeout. A failed request becomes status 0 with an empty
/// body so the extension can still render the ones that did load. Header values, which carry the owner's
/// tokens, go only to the helper and are never logged.
enum ExtensionFetcher {
    private static let pendingLock = NSLock()
    private static var pendingReads: [ObjectIdentifier: () -> Void] = [:]

    /// Stops every extension GET still in flight, for a list run a newer query replaced. Each completes as
    /// a failed fetch, and closing its connection makes the helper cancel the transfer. POSTs from row
    /// actions are left to finish, since the server may already be acting on them.
    static func cancelReads() {
        pendingLock.lock(); let pending = Array(pendingReads.values); pendingReads = [:]; pendingLock.unlock()
        pending.forEach { $0() }
    }

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
        call(timeout: 35, cancellable: request.method == "GET", { proxy, reply in
            proxy.request(url: request.url.absoluteString, method: request.method, body: request.body, headers: request.headers,
                          allowedHosts: hosts, maximumBytes: ExtensionNetwork.maximumResponseBytes, reply: reply)
        }) { data, status, error in
            let body = error == nil ? data : nil
            let text = body.flatMap { String(data: $0, encoding: .utf8) }
            completion(ExtensionNetwork.Response(url: request.url.absoluteString, status: body == nil || text == nil ? 0 : status, body: text ?? ""))
        }
    }

    /// Downloads a row's copy as raw bytes, which may be an image, for `ExtensionManager.copy`. The owner
    /// asked for it, so a newer query never cancels it. Completes with no data and the HTTP status (0 when
    /// none) when the helper refused it, failed or stopped past the size limit.
    static func fetchData(_ request: ExtensionRequest, hosts: [String], completion: @escaping (Data?, Int) -> Void) {
        call(timeout: 35, { proxy, reply in
            proxy.request(url: request.url.absoluteString, method: request.method, body: request.body, headers: request.headers,
                          allowedHosts: hosts, maximumBytes: ExtensionItemCopy.maximumDownloadBytes, reply: reply)
        }) { data, status, error in completion(error == nil ? data : nil, status) }
    }

    /// How a row image fetch ended: the helper's PNG thumbnail, SVG markup the helper checked and Volant
    /// only forwards to the extension helper to draw (`svg`), SVG the helper refused (`svgRefused`), a
    /// failure the helper reported (an HTTP error, a download that is not an image, a timeout), or a stop
    /// with no answer (a newer query cancelled it, or the connection ended), which may be tried again later.
    enum RowImageReply: Equatable {
        case thumbnail(Data)
        case svg(Data)
        case svgRefused
        case failed(status: Int)
        case stopped
    }

    /// Asks the fetch helper for a row image's thumbnail. It runs among the cancellable reads, so a newer
    /// query in the extension stops it along with that run's fetches.
    static func fetchRowImage(_ request: ExtensionRequest, hosts: [String], completion: @escaping (RowImageReply) -> Void) {
        let marked = SVGMark()
        call(timeout: 35, cancellable: true, { proxy, reply in
            proxy.rowImage(url: request.url.absoluteString, headers: request.headers, allowedHosts: hosts) { data, isSVG, status, error in
                marked.set(isSVG)
                reply(data, status, error)
            }
        }) { data, status, error in
            let isSVG = marked.value
            switch (data, error) {
            case (let data?, nil): completion(isSVG ? .svg(data) : .thumbnail(data))
            case (nil, _?) where isSVG: completion(.svgRefused)
            case _ where error != nil || status != 0: completion(.failed(status: status))
            default: completion(.stopped)
            }
        }
    }

    /// Whether the fetch helper marked its reply as SVG, set on the reply's queue and read on the main queue.
    private final class SVGMark: @unchecked Sendable {
        private let lock = NSLock()
        private var marked = false
        var value: Bool { lock.lock(); defer { lock.unlock() }; return marked }
        func set(_ value: Bool) { lock.lock(); marked = value; lock.unlock() }
    }

    /// Reads one extension catalog file through the helper's fixed-location method. Anything other than
    /// a complete 200 response is an error; the caller verifies signatures and hashes.
    static func catalogFile(_ path: String, maximumBytes: Int, completion: @escaping (Result<Data, Error>) -> Void) {
        call(timeout: 45, { proxy, reply in
            proxy.fetchCatalogFile(path: path, maximumBytes: maximumBytes, reply: reply)
        }) { data, status, error in
            if let data, error == nil, status == 200 { completion(.success(data)); return }
            let detail = error ?? (status == 0 ? String(localized: "The fetch helper did not answer.", comment: "Extension catalog error detail") : String(localized: "The server answered \(status).", comment: "Extension catalog error detail; the value is an HTTP status code"))
            completion(.failure(ExtensionCatalogError.unavailable(detail)))
        }
    }

    /// One short-lived helper connection that completes exactly once, on the main queue: with the
    /// helper's reply, or with no data and status 0 after a connection failure, the timeout, or, when
    /// `cancellable`, `cancelReads`.
    private static func call(timeout: TimeInterval, cancellable: Bool = false, _ request: (VolantFetchHostProtocol, @escaping (Data?, Int, String?) -> Void) -> Void,
                             completion: @escaping (Data?, Int, String?) -> Void) {
        let connection = NSXPCConnection(serviceName: "com.mysticcoders.volant.FetchHost")
        connection.remoteObjectInterface = NSXPCInterface(with: VolantFetchHostProtocol.self)
        let lock = NSLock()
        var finished = false
        let finish: (Data?, Int, String?) -> Void = { data, status, error in
            lock.lock(); defer { lock.unlock() }
            guard !finished else { return }
            finished = true
            if cancellable { pendingLock.lock(); pendingReads[ObjectIdentifier(connection)] = nil; pendingLock.unlock() }
            connection.invalidate()
            DispatchQueue.main.async { completion(data, status, error) }
        }
        if cancellable { pendingLock.lock(); pendingReads[ObjectIdentifier(connection)] = { finish(nil, 0, nil) }; pendingLock.unlock() }
        connection.invalidationHandler = { finish(nil, 0, nil) }
        connection.interruptionHandler = { finish(nil, 0, nil) }
        connection.resume()
        DispatchQueue.main.asyncAfter(deadline: .now() + timeout) { finish(nil, 0, String(localized: "The request timed out.", comment: "Extension network error detail")) }
        guard let proxy = connection.remoteObjectProxyWithErrorHandler({ _ in finish(nil, 0, nil) }) as? VolantFetchHostProtocol else {
            finish(nil, 0, nil); return
        }
        request(proxy, finish)
    }
}
