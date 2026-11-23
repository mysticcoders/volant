import Combine
import Foundation
import VolantCore

/// The Worktrees command's data: the owner's linked git worktrees, read through the agent helper
/// because the sandboxed app can't read other folders or run git. Rows arrive first; sizes, last
/// commit times and change counts follow a few at a time. Kept only in memory, never logged,
/// persisted or synced. Acts on nothing.
final class WorktreesModel: ObservableObject {
    @Published private(set) var worktrees: [Worktree] = []
    @Published private(set) var details: [String: WorktreeDetails] = [:]
    @Published private(set) var changes: [String: Int] = [:]
    @Published private(set) var loading = false
    @Published private(set) var measuring = false
    @Published private(set) var message: String?
    private var refreshedAt: Date?
    private var connection: NSXPCConnection?
    private var request = UUID()
    var loadOverride: (([String], @escaping ([Worktree]?, String?) -> Void) -> Void)?
    var detailsOverride: (([String], @escaping ([String: WorktreeDetails]?) -> Void) -> Void)?
    var changesOverride: (([String], @escaping ([String: RepositoryState]?) -> Void) -> Void)?

    deinit { connection?.invalidate() }

    static let home: String = UserHome.path

    var sizes: [String: Int64] { details.compactMapValues(\.size) }

    private func proxy(failure: @escaping () -> Void) -> VolantAgentHostProtocol? {
        guard ProcessInfo.processInfo.environment["VOLANT_UNIT_TESTING"] != "1" else { return nil }
        if connection == nil {
            let client = NSXPCConnection(serviceName: "com.mysticcoders.volant.AgentHost")
            client.remoteObjectInterface = NSXPCInterface(with: VolantAgentHostProtocol.self)
            client.resume()
            connection = client
        }
        return connection?.remoteObjectProxyWithErrorHandler { [weak self] _ in
            Task { @MainActor in
                self?.connection?.invalidate(); self?.connection = nil
                failure()
            }
        } as? VolantAgentHostProtocol
    }

    /// Lists worktrees again unless a list finished in the last ten seconds, then measures the ones
    /// not measured yet (all of them when `force`). `folders` are agent working folders the launcher
    /// already knows, passed as hints for finding repositories. A stale reply is dropped.
    func refresh(folders: [String], force: Bool = false) {
        guard !loading, force || refreshedAt.map({ Date().timeIntervalSince($0) > 10 }) ?? true else { return }
        loading = true
        let token = UUID(); request = token
        if force { details = [:]; changes = [:] }
        let hints = Array(Set(folders.filter { $0.hasPrefix("/") }).sorted().prefix(Worktrees.maximumFolders))
        let finish: ([Worktree]?, String?) -> Void = { [weak self] values, error in
            Task { @MainActor in
                guard let self, self.request == token, self.loading else { return }
                self.loading = false
                self.refreshedAt = Date()
                self.message = error
                guard let values else { return }
                self.worktrees = values
                let listed = Set(values.map(\.path))
                self.details = self.details.filter { listed.contains($0.key) }
                self.changes = self.changes.filter { listed.contains($0.key) }
                self.measure(token: token)
                self.countChanges(token: token)
            }
        }
        if let loadOverride { loadOverride(hints, finish); return }
        let failure = { finish(nil, String(localized: "Couldn’t read git worktrees. Try Refresh.")) }
        guard let proxy = proxy(failure: failure), let data = try? JSONEncoder().encode(hints) else { failure(); return }
        proxy.listWorktrees(folders: data) { data, error in
            guard error == nil, let data, data.count <= 4_000_000,
                  let values = try? JSONDecoder().decode([Worktree].self, from: data) else { failure(); return }
            finish(Array(values.prefix(Worktrees.maximumWorktrees)), nil)
        }
    }

    /// Measures unmeasured, existing worktrees a batch at a time, so sizes fill in as they finish.
    private func measure(token: UUID) {
        guard request == token else { measuring = false; return }
        let batch = Array(worktrees.filter { !$0.stale && details[$0.path] == nil }.map(\.path).prefix(Worktrees.maximumDetailPaths))
        guard !batch.isEmpty else { measuring = false; return }
        measuring = true
        let finish: ([String: WorktreeDetails]?) -> Void = { [weak self] values in
            Task { @MainActor in
                guard let self, self.request == token else { return }
                var updated = self.details
                for path in batch { updated[path] = values?[path] ?? WorktreeDetails(size: nil, sizeComplete: false) }
                self.details = updated
                self.measure(token: token)
            }
        }
        if let detailsOverride { detailsOverride(batch, finish); return }
        guard let proxy = proxy(failure: { finish(nil) }), let data = try? JSONEncoder().encode(batch) else { finish(nil); return }
        proxy.worktreeDetails(paths: data) { data, error in
            guard error == nil, let data, data.count <= 200_000,
                  let values = try? JSONDecoder().decode([String: WorktreeDetails].self, from: data) else { finish(nil); return }
            finish(values)
        }
    }

    /// Counts uncommitted changes through the helper's existing repository-status call.
    private func countChanges(token: UUID) {
        let paths = Array(worktrees.filter { !$0.stale && changes[$0.path] == nil }.map(\.path).prefix(RepositoryStateLimit.paths))
        guard !paths.isEmpty else { return }
        let finish: ([String: RepositoryState]?) -> Void = { [weak self] values in
            Task { @MainActor in
                guard let self, self.request == token, let values else { return }
                var updated = self.changes
                for (path, state) in values where paths.contains(path) { updated[path] = state.changed }
                self.changes = updated
                if values.count == paths.count { self.countChanges(token: token) }
            }
        }
        if let changesOverride { changesOverride(paths, finish); return }
        guard let proxy = proxy(failure: { finish(nil) }), let data = try? JSONEncoder().encode(paths) else { return }
        proxy.repositoryStates(paths: data) { data, error in
            guard error == nil, let data, let values = try? JSONDecoder().decode([String: RepositoryState].self, from: data) else { finish(nil); return }
            finish(values)
        }
    }

    /// The row's second line: repository, abbreviated path, size, uncommitted changes and the last
    /// commit's age, each when known.
    func detail(for worktree: Worktree, now: Date = Date()) -> String {
        var parts = [worktree.repositoryName, worktree.abbreviatedPath(home: Self.home)]
        if worktree.stale { return parts.joined(separator: " · ") }
        if let info = details[worktree.path], let size = info.size { parts.append(Worktrees.formatSize(size, complete: info.sizeComplete)) }
        else if measuring { parts.append(String(localized: "measuring…", comment: "Worktree row while its size is being read")) }
        if let count = changes[worktree.path], count > 0 {
            parts.append(String(localized: "\(count, specifier: "%lld") uncommitted", comment: "Worktree row: number of uncommitted changes"))
        }
        if let date = details[worktree.path]?.lastCommit { parts.append(Worktrees.age(of: date, now: now)) }
        return parts.joined(separator: " · ")
    }

    /// The right-hand label: In Use, Stale, Locked, Uncommitted or Clean.
    func label(for worktree: Worktree, holder: String?) -> String {
        if holder != nil { return String(localized: "In Use", comment: "Worktree row label: a server or agent is working in it") }
        if worktree.stale { return String(localized: "Stale", comment: "Worktree row label: registered with git but its folder is gone") }
        if worktree.locked { return String(localized: "Locked", comment: "Worktree row label: locked with git worktree lock") }
        guard let count = changes[worktree.path] else { return "" }
        return count > 0 ? String(localized: "Uncommitted", comment: "Worktree row label: has uncommitted changes")
            : String(localized: "Clean", comment: "Worktree row label: no uncommitted changes")
    }
}
