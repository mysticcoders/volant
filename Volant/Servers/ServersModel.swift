import Combine
import Foundation
import VolantCore

/// The Servers command's data: the owner's listening TCP servers, read through the agent helper
/// because the sandboxed app can't see other processes' sockets. Read when the command opens and
/// on Refresh, kept only in memory, and never logged.
final class ServersModel: ObservableObject {
    @Published private(set) var servers: [ListeningServer] = []
    @Published private(set) var loading = false
    @Published private(set) var message: String?
    private var refreshedAt: Date?
    private var connection: NSXPCConnection?
    private var request = UUID()
    var loadOverride: ((@escaping ([ListeningServer]?, String?) -> Void) -> Void)?

    deinit { connection?.invalidate() }

    /// The owner's real home folder for shortening paths. Inside the sandbox `NSHomeDirectory()`
    /// is the app's container, which no server's working folder is in.
    static let home: String = getpwuid(getuid()).flatMap { $0.pointee.pw_dir.map { String(cString: $0) } } ?? NSHomeDirectory()

    /// The servers for a Servers query: runtimes first, macOS services only after `all`.
    func matches(_ query: String) -> [ListeningServer] {
        guard let term = ListeningServers.queryTerm(query) else { return [] }
        return ListeningServers.arrange(servers, matching: term.text, all: term.all)
    }

    private func proxy(failure: @escaping () -> Void) -> VolantAgentHostProtocol? {
        guard ProcessInfo.processInfo.environment["VOLANT_UNIT_TESTING"] != "1" else { return nil }
        if connection == nil {
            let client = NSXPCConnection(serviceName: "com.mysticcoders.volant.AgentHost")
            client.remoteObjectInterface = NSXPCInterface(with: VolantAgentHostProtocol.self)
            client.resume()
            connection = client
        }
        return connection?.remoteObjectProxyWithErrorHandler { [weak self] _ in
            DispatchQueue.main.async {
                self?.connection?.invalidate(); self?.connection = nil
                failure()
            }
        } as? VolantAgentHostProtocol
    }

    /// Reads the servers again unless a read finished in the last two seconds. Ports come and go
    /// as servers start and stop, so nothing is cached longer; a stale reply is dropped.
    func refresh(force: Bool = false) {
        guard !loading, force || refreshedAt.map({ Date().timeIntervalSince($0) > 2 }) ?? true else { return }
        loading = true
        let token = UUID(); request = token
        let finish: ([ListeningServer]?, String?) -> Void = { [weak self] values, error in
            DispatchQueue.main.async {
                guard let self, self.request == token, self.loading else { return }
                self.loading = false
                self.refreshedAt = Date()
                self.message = error
                if let values { self.servers = values }
            }
        }
        if let loadOverride { loadOverride(finish); return }
        let failure = { finish(nil, String(localized: "Couldn’t read listening servers. Try Refresh.")) }
        guard let proxy = proxy(failure: failure) else { failure(); return }
        proxy.listListeningServers { data, error in
            guard error == nil, let data, data.count <= 2_000_000,
                  let values = try? JSONDecoder().decode([ListeningServer].self, from: data) else { failure(); return }
            finish(Array(values.prefix(ListeningServers.maximumServers)), nil)
        }
    }
}
