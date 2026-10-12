import Foundation
import VolantCore

/// Fetches a network extension's planned URLs through the sandboxed VolantFetchHost, one short-lived
/// connection per URL. Volant itself has no network access. Each fetch completes exactly once: with the
/// helper's reply, a connection failure, or a timeout. A failed fetch becomes status 0 with an empty body
/// so the extension can still render the URLs that did load.
enum ExtensionFetcher {
    static func fetch(_ urls: [URL], hosts: [String], completion: @escaping ([ExtensionNetwork.Response]) -> Void) {
        var responses = [ExtensionNetwork.Response?](repeating: nil, count: urls.count)
        let group = DispatchGroup()
        for (index, url) in urls.enumerated() {
            group.enter()
            fetchOne(url, hosts: hosts) { response in
                responses[index] = response
                group.leave()
            }
        }
        group.notify(queue: .main) { completion(responses.compactMap { $0 }) }
    }

    private static func fetchOne(_ url: URL, hosts: [String], completion: @escaping (ExtensionNetwork.Response) -> Void) {
        let connection = NSXPCConnection(serviceName: "com.mysticcoders.volant.FetchHost")
        connection.remoteObjectInterface = NSXPCInterface(with: VolantFetchHostProtocol.self)
        let lock = NSLock()
        var finished = false
        let finish: (Data?, Int) -> Void = { data, status in
            lock.lock(); defer { lock.unlock() }
            guard !finished else { return }
            finished = true
            connection.invalidate()
            let text = data.flatMap { String(data: $0, encoding: .utf8) }
            let response = ExtensionNetwork.Response(url: url.absoluteString, status: data != nil && text == nil ? 0 : status, body: text ?? "")
            DispatchQueue.main.async { completion(response) }
        }
        connection.invalidationHandler = { finish(nil, 0) }
        connection.interruptionHandler = { finish(nil, 0) }
        connection.resume()
        DispatchQueue.main.asyncAfter(deadline: .now() + 35) { finish(nil, 0) }
        let proxy = connection.remoteObjectProxyWithErrorHandler { _ in finish(nil, 0) } as? VolantFetchHostProtocol
        proxy?.fetch(url: url.absoluteString, allowedHosts: hosts, maximumBytes: ExtensionNetwork.maximumResponseBytes) { data, status, error in
            finish(error == nil ? data : nil, error == nil ? status : 0)
        }
    }
}
