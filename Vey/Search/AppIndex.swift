import AppKit

struct AppEntry: Identifiable, Hashable {
    let id: String
    let name: String
    let url: URL
    let lastUsed: Date?
}

/// Application index built from Spotlight metadata, which works inside the sandbox without folder access.
/// Only bundles in real application folders are indexed, so helper and system-internal apps stay out.
final class AppIndex: NSObject {
    private(set) var apps: [AppEntry] = []
    private let query = NSMetadataQuery()

    static let applicationRoots: [String] = {
        var roots = ["/Applications/", "/System/Applications/", "/System/Applications/Utilities/", "/Applications/Utilities/"]
        roots.append(NSHomeDirectory() + "/Applications/")
        if let real = try? FileManager.default.destinationOfSymbolicLink(atPath: NSHomeDirectory()) { roots.append(real + "/Applications/") }
        return roots
    }()

    func start() {
        query.predicate = NSPredicate(format: "kMDItemContentType == 'com.apple.application-bundle'")
        query.searchScopes = [NSMetadataQueryLocalComputerScope]
        NotificationCenter.default.addObserver(self, selector: #selector(gathered), name: .NSMetadataQueryDidFinishGathering, object: query)
        NotificationCenter.default.addObserver(self, selector: #selector(gathered), name: .NSMetadataQueryDidUpdate, object: query)
        query.start()
    }

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

    func search(_ text: String, limit: Int = 8) -> [AppEntry] {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return [] }
        return apps
            .compactMap { app -> (AppEntry, Int)? in
                FuzzyMatcher.score(query: trimmed, candidate: app.name).map { (app, $0) }
            }
            .sorted { $0.1 > $1.1 }
            .prefix(limit)
            .map { $0.0 }
    }

    func launch(_ app: AppEntry) {
        RecentApps.record(app.id)
        NSWorkspace.shared.openApplication(at: app.url, configuration: NSWorkspace.OpenConfiguration())
    }

    /// Most recently used apps by Spotlight's last-used date, which LaunchServices updates however the app was opened.
    /// Vey's own launches count immediately, before Spotlight catches up.
    func suggestions(limit: Int = 6) -> [AppEntry] {
        let ownRecents = RecentApps.paths()
        func stamp(_ app: AppEntry) -> Date {
            if let i = ownRecents.firstIndex(of: app.id) { return Date().addingTimeInterval(-Double(i)) }
            return app.lastUsed ?? .distantPast
        }
        return apps
            .filter { stamp($0) > .distantPast }
            .sorted { stamp($0) > stamp($1) }
            .prefix(limit)
            .map { $0 }
    }
}
