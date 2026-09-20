import AppKit
import Combine
import VolantCore

struct AppEntry: Identifiable, Hashable {
    let id: String
    let name: String
    let url: URL
    let lastUsed: Date?
}

/// Application index built from Spotlight metadata, which works inside the sandbox without folder access.
/// Only bundles in real application folders are indexed, so helper and system-internal apps stay out.
final class AppIndex: NSObject {
    @Published private(set) var unavailable = false
    private let startQuery: (NSMetadataQuery) -> Bool
    private var observing = false
    private var started = false
    @Published private(set) var apps: [AppEntry] = []
    private let query = NSMetadataQuery()
    private let launchOverride: ((AppEntry) -> Void)?
    init(entries: [AppEntry] = [], launch: ((AppEntry) -> Void)? = nil, startQuery: @escaping (NSMetadataQuery) -> Bool = { $0.start() }) {
        self.startQuery = startQuery
        self.apps = entries
        self.launchOverride = launch
        super.init()
    }

    /// Imported aliases contain a path and must never fuzzy-match a different app.
    func resolveAlias(_ target: String) -> AppEntry? {
        if target.hasPrefix("/") { return apps.first { $0.url.path == target } }
        return search(target, limit: 1).first
    }

    static let applicationRoots: [String] = {
        var roots = ["/Applications/", "/System/Applications/", "/System/Applications/Utilities/", "/Applications/Utilities/"]
        roots.append(NSHomeDirectory() + "/Applications/")
        if let real = try? FileManager.default.destinationOfSymbolicLink(atPath: NSHomeDirectory()) { roots.append(real + "/Applications/") }
        return roots
    }()

    func start() {
        guard !started else { return }
        query.predicate = NSPredicate(format: "kMDItemContentType == 'com.apple.application-bundle'")
        query.searchScopes = [NSMetadataQueryLocalComputerScope]
        if !observing {
            NotificationCenter.default.addObserver(self, selector: #selector(gathered), name: .NSMetadataQueryDidFinishGathering, object: query)
            NotificationCenter.default.addObserver(self, selector: #selector(gathered), name: .NSMetadataQueryDidUpdate, object: query)
            observing = true
        }
        started = startQuery(query)
        unavailable = !started
    }

    deinit { query.stop(); NotificationCenter.default.removeObserver(self) }

    @objc private func gathered() {
        query.disableUpdates()
        defer { query.enableUpdates() }
        var seen = Set<String>()
        var result: [AppEntry] = []
        for i in 0..<query.resultCount {
            guard let item = query.result(at: i) as? NSMetadataItem,
                  let path = item.value(forAttribute: NSMetadataItemPathKey) as? String,
                  AppIndex.isUserFacingApp(path) else { continue }
            let name = (item.value(forAttribute: NSMetadataItemDisplayNameKey) as? String)
                ?? URL(fileURLWithPath: path).deletingPathExtension().lastPathComponent
            let clean = name.hasSuffix(".app") ? String(name.dropLast(4)) : name
            guard seen.insert(path).inserted else { continue }
            let lastUsed = item.value(forAttribute: NSMetadataItemLastUsedDateKey) as? Date
            result.append(AppEntry(id: path, name: clean, url: URL(fileURLWithPath: path), lastUsed: lastUsed))
        }
        apps = result.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    /// An app the user would launch: directly inside one of the application folders (one level of subfolder allowed), not nested in another bundle.
    static func isUserFacingApp(_ path: String) -> Bool {
        guard path.hasSuffix(".app"), !path.contains("/Contents/") else { return false }
        for root in applicationRoots where path.hasPrefix(root) {
            let rest = path.dropFirst(root.count)
            return rest.split(separator: "/").count <= 2
        }
        return false
    }

    /// Fuzzy match, then learned ranking: each past use adds a decayed bonus, and the app last chosen
    /// for this exact query is pinned to the top.
    func search(_ text: String, limit: Int = 8, usage: UsageStore? = nil) -> [AppEntry] {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return [] }
        let pinned = usage?.choice(forQuery: trimmed)
        return apps
            .compactMap { app -> (AppEntry, Double)? in
                guard let base = FuzzyMatcher.score(query: trimmed, candidate: app.name) else { return nil }
                var score = Double(base)
                if let usage { score += 25 * min(usage.score("app:" + app.id), 4) }
                if pinned == "app:" + app.id { score += 1000 }
                return (app, score)
            }
            .sorted { $0.1 > $1.1 }
            .prefix(limit)
            .map { $0.0 }
    }

    func launch(_ app: AppEntry) {
        if let launchOverride { launchOverride(app); return }
        NSWorkspace.shared.openApplication(at: app.url, configuration: NSWorkspace.OpenConfiguration())
    }

    /// Most recently used apps by Spotlight's last-used date, which LaunchServices updates however the app was opened.
    /// Volant's own launches count immediately, before Spotlight catches up.
    /// Learned first: apps by frecency of being chosen here, then the system's last-used dates to fill.
    func suggestions(limit: Int = 6, usage: UsageStore? = nil) -> [AppEntry] {
        let byPath = Dictionary(uniqueKeysWithValues: apps.map { ($0.id, $0) })
        var out: [AppEntry] = []
        if let usage {
            for key in usage.top(prefix: "app:", limit: limit) {
                if let app = byPath[String(key.dropFirst(4))], !out.contains(app) { out.append(app) }
            }
        }
        let bySystem = apps.filter { $0.lastUsed != nil }.sorted { ($0.lastUsed ?? .distantPast) > ($1.lastUsed ?? .distantPast) }
        for app in bySystem where out.count < limit && !out.contains(app) { out.append(app) }
        return Array(out.prefix(limit))
    }
}
