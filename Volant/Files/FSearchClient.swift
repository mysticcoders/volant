import Foundation
import VolantCore

/// The optional fsearch file search: asks a running fsearch daemon through the agent helper, which is
/// not sandboxed and can reach its socket. Volant never installs or starts fsearch. Every call opens a
/// short-lived connection and completes exactly once on the main queue, with the helper's answer or an
/// error after a timeout. Tests replace `call`.
final class FSearchClient {
    static let shared = FSearchClient()

    enum Request { case search(String, limit: Int), status, opened(String) }

    var call: (Request, @escaping (Data?, String?) -> Void) -> Void = FSearchClient.helperCall

    /// Matching files, folders first only by fsearch's own ranking, as launcher entries.
    func search(_ query: String, limit: Int, completion: @escaping (Result<[FileEntry], FSearchError>) -> Void) {
        call(.search(query, limit: limit)) { data, error in
            guard let data, let hits = try? JSONDecoder().decode([FSearch.Hit].self, from: data) else {
                completion(.failure(error.map { .daemon($0) } ?? .malformed)); return
            }
            completion(.success(hits.map(FSearchClient.entry)))
        }
    }

    /// The daemon's status, or the message explaining why it can't be reached.
    func status(_ completion: @escaping (Result<FSearch.Status, FSearchError>) -> Void) {
        call(.status) { data, error in
            guard let data, let status = try? JSONDecoder().decode(FSearch.Status.self, from: data) else {
                completion(.failure(error.map { .daemon($0) } ?? .malformed)); return
            }
            completion(.success(status))
        }
    }

    /// Tells fsearch a file was opened from Volant, so it ranks higher. Failures are ignored.
    func opened(_ path: String) { call(.opened(path)) { _, _ in } }

    static func entry(_ hit: FSearch.Hit) -> FileEntry {
        let url = URL(fileURLWithPath: hit.path, isDirectory: hit.isFolder)
        return FileEntry(id: hit.path, name: url.lastPathComponent, url: url, kind: hit.isFolder ? String(localized: "Folder", comment: "File kind shown beside a folder in file search results") : "")
    }

    private static func helperCall(_ request: Request, completion: @escaping (Data?, String?) -> Void) {
        let connection = NSXPCConnection(serviceName: "com.mysticcoders.volant.AgentHost")
        connection.remoteObjectInterface = NSXPCInterface(with: VolantAgentHostProtocol.self)
        let lock = NSLock()
        var finished = false
        let finish: (Data?, String?) -> Void = { data, error in
            lock.lock(); defer { lock.unlock() }
            guard !finished else { return }
            finished = true
            connection.invalidate()
            DispatchQueue.main.async { completion(data, HostMessage.display(error)) }
        }
        connection.invalidationHandler = { finish(nil, String(localized: "The agent helper is unavailable.", comment: "fsearch file search error")) }
        connection.interruptionHandler = { finish(nil, String(localized: "The agent helper is unavailable.", comment: "fsearch file search error")) }
        connection.resume()
        DispatchQueue.main.asyncAfter(deadline: .now() + 4) { finish(nil, FSearchError.timedOut.localizedDescription) }
        guard let proxy = connection.remoteObjectProxyWithErrorHandler({ _ in finish(nil, String(localized: "The agent helper is unavailable.", comment: "fsearch file search error")) }) as? VolantAgentHostProtocol else {
            finish(nil, String(localized: "The agent helper is unavailable.", comment: "fsearch file search error")); return
        }
        switch request {
        case .search(let query, let limit): proxy.fsearchSearch(query: query, limit: limit, reply: finish)
        case .status: proxy.fsearchStatus(reply: finish)
        case .opened(let path): proxy.fsearchOpened(path: path) { finish(nil, $0) }
        }
    }
}
