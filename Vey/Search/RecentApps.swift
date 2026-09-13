import Foundation

/// Most-recently-launched apps, by path, for the empty-query Suggestions list.
enum RecentApps {
    private static let key = "recentAppPaths"
    private static let cap = 12

    static func paths() -> [String] {
        UserDefaults.standard.stringArray(forKey: key) ?? []
    }

    static func record(_ path: String) {
        var list = paths().filter { $0 != path }
        list.insert(path, at: 0)
        UserDefaults.standard.set(Array(list.prefix(cap)), forKey: key)
    }
}
