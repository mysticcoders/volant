import Foundation

/// User configuration, read from a JSON file in the app's sandbox container. General settings also have a native panel.
public struct Preferences: Codable {
    public var summonHotKey: String = "option+space"
    public var emojiHotKey: String = ""
    public var notesHotKey: String = "option+n"
    public var appHotKeys: [AppHotKey] = []
    public var clipboardRetention: Int = 500
    public var showOnLaunch: Bool = true
    public var showInDock: Bool = true
    public var statusBar = StatusBarConfiguration()
    // Compatibility for existing callers and older configuration files.
    public var promotedHarness: String? {
        get { statusBar.sources.contains("herdr") ? statusBar.herdrFilter : nil }
        set {
            statusBar.sources.removeAll { $0 == "herdr" }
            if let newValue { statusBar.sources.append("herdr"); statusBar.herdrFilter = newValue }
        }
    }
    public static let harnessOptions: [(id: String, title: String)] = [("all", "All Herdr agents"), ("opencode", "OpenCode"), ("cursor", "Cursor"), ("claude", "Claude Code"), ("codex", "Codex")]
    public var snippets: [Snippet] = []
    public var quicklinks: [Quicklink] = [Quicklink(name: "Google", url: "https://www.google.com/search?q={query}")]
    public var favoriteApps: [String] = []
    public var aliases: [String: String] = [:]
    public var appearance: Appearance = Appearance()
    public var help: String = "Edit and choose Reload Configuration in Settings. Hotkeys: cmd|ctrl|option|shift|meh|hyper + key. App hotkeys use the bundle identifier. Snippets: {date} {isodate} {time} {datetime} {clipboard} {uuid}. Quicklinks: {query}. Aliases map a word to an app name or query. Appearance: scale 0.8–1.4, opacity 0.5–1.0."

    public enum CodingKeys: String, CodingKey {
        case favoriteApps, summonHotKey, notesHotKey, emojiHotKey, appHotKeys, clipboardRetention, showOnLaunch, showInDock, statusBar, snippets, quicklinks, aliases, appearance
        case help = "_help"
    }

    public static var supportDirectory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        // Preserve the original storage location across the Volant rebrand.
        let dir = base.appendingPathComponent("Vey", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    public static var configURL: URL { supportDirectory.appendingPathComponent("config.json") }

    /// Missing keys fall back to defaults, so a config written by an older version keeps working.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = Preferences()
        summonHotKey = try c.decodeIfPresent(String.self, forKey: .summonHotKey) ?? d.summonHotKey
        notesHotKey = try c.decodeIfPresent(String.self, forKey: .notesHotKey) ?? d.notesHotKey
        emojiHotKey = try c.decodeIfPresent(String.self, forKey: .emojiHotKey) ?? d.emojiHotKey
        appHotKeys = try c.decodeIfPresent([AppHotKey].self, forKey: .appHotKeys) ?? d.appHotKeys
        clipboardRetention = try c.decodeIfPresent(Int.self, forKey: .clipboardRetention) ?? d.clipboardRetention
        showOnLaunch = try c.decodeIfPresent(Bool.self, forKey: .showOnLaunch) ?? d.showOnLaunch
        showInDock = try c.decodeIfPresent(Bool.self, forKey: .showInDock) ?? d.showInDock
        statusBar = try c.decodeIfPresent(StatusBarConfiguration.self, forKey: .statusBar) ?? StatusBarConfiguration()
        if !c.contains(.statusBar) {
            let legacy = try decoder.container(keyedBy: LegacyKeys.self)
            if let id = try legacy.decodeIfPresent(String.self, forKey: .promotedHarness), Self.harnessOptions.contains(where: { $0.id == id }) { promotedHarness = id }
        }
        if !Self.harnessOptions.contains(where: { $0.id == statusBar.herdrFilter }) { statusBar.herdrFilter = "all" }
        snippets = try c.decodeIfPresent([Snippet].self, forKey: .snippets) ?? d.snippets
        quicklinks = try c.decodeIfPresent([Quicklink].self, forKey: .quicklinks) ?? d.quicklinks
        favoriteApps = try c.decodeIfPresent([String].self, forKey: .favoriteApps) ?? []
        aliases = try c.decodeIfPresent([String: String].self, forKey: .aliases) ?? d.aliases
        appearance = try c.decodeIfPresent(Appearance.self, forKey: .appearance) ?? d.appearance
        help = try c.decodeIfPresent(String.self, forKey: .help) ?? d.help
    }

    public init() {}

    /// Patch a single setting, preserving externally edited and unknown configuration fields.
    public static func updateBoolean(_ key: String, value: Bool, at url: URL = configURL) throws {
        precondition(["showInDock", "showOnLaunch"].contains(key))
        let data = try Data(contentsOf: url)
        guard var object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw CocoaError(.fileReadCorruptFile)
        }
        object[key] = value
        let updated = try JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys])
        // Reject invalid known settings before changing the file.
        _ = try JSONDecoder().decode(Preferences.self, from: updated)
        try updated.write(to: url, options: .atomic)
    }

    /// Patch only this app's membership against the latest document.
    public static func updateFavorite(_ id: String, expected: Bool, at url: URL = configURL) throws -> Preferences {
        let data = try Data(contentsOf: url)
        let current = try JSONDecoder().decode(Preferences.self, from: data)
        guard current.favoriteApps.contains(id) == expected else { throw CocoaError(.fileWriteFileExists) }
        guard var object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw CocoaError(.fileReadCorruptFile) }
        var favorites = current.favoriteApps.filter { $0 != id }
        if !expected { favorites.append(id) }
        object["favoriteApps"] = favorites
        let updated = try JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys])
        let result = try JSONDecoder().decode(Preferences.self, from: updated)
        try updated.write(to: url, options: .atomic)
        return result
    }

    private enum LegacyKeys: String, CodingKey { case promotedHarness }

    public static func updatePromotedHarness(_ harness: String?, at url: URL = configURL) throws {
        guard harness == nil || harnessOptions.contains(where: { $0.id == harness }) else { throw CocoaError(.fileReadCorruptFile) }
        try updateStatusBar(enabled: harness != nil, filter: harness, at: url)
    }

    public static func updateStatusBar(source: String = "herdr", enabled: Bool? = nil, filter: String? = nil, at url: URL = configURL) throws {
        guard ["herdr", "ai-chat"].contains(source) else { throw CocoaError(.fileReadCorruptFile) }
        if let filter, !harnessOptions.contains(where: { $0.id == filter }) { throw CocoaError(.fileReadCorruptFile) }
        let data = try Data(contentsOf: url)
        let current = try JSONDecoder().decode(Preferences.self, from: data)
        guard var object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw CocoaError(.fileReadCorruptFile) }
        var bar = object["statusBar"] as? [String: Any] ?? [:]
        var sources = current.statusBar.sources
        if let enabled {
            sources.removeAll { $0 == source }
            if enabled { sources.append(source) }
        }
        bar["sources"] = sources
        bar["herdrFilter"] = filter ?? current.statusBar.herdrFilter
        object["statusBar"] = bar
        object.removeValue(forKey: "promotedHarness")
        let updated = try JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys])
        _ = try JSONDecoder().decode(Preferences.self, from: updated)
        try updated.write(to: url, options: .atomic)
    }

    /// Last load problem, shown in the menu bar. A malformed file is left in place, never replaced.
    public static var loadError: String? = nil

    /// Loads the config. Writes the defaults only when no file exists at all.
    public static func load() -> Preferences {
        loadError = nil
        if let data = try? Data(contentsOf: configURL) {
            do {
                return try JSONDecoder().decode(Preferences.self, from: data)
            } catch {
                loadError = "config.json could not be read (\(error.localizedDescription)); using defaults without overwriting it."
                return Preferences()
            }
        }
        let defaults = Preferences()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let data = try? encoder.encode(defaults) {
            try? data.write(to: configURL, options: .atomic)
        }
        return defaults
    }
}

public struct Appearance: Codable, Equatable {
    /// 1.0 is the default 750×480 panel; 0.8 to 1.4 are sensible.
    public var scale: Double = 1.0
    /// 1.0 is the system material; lower values let the desktop show through more.
    public var opacity: Double = 1.0

    public init(scale: Double = 1.0, opacity: Double = 1.0) {
        self.scale = scale
        self.opacity = opacity
    }
}

public struct AppHotKey: Codable {
    public var bundleIdentifier: String
    public var hotKey: String

    public init(bundleIdentifier: String, hotKey: String) {
        self.bundleIdentifier = bundleIdentifier
        self.hotKey = hotKey
    }
}

/// Sources are independent so future status providers need not reuse Herdr settings.
public struct StatusBarConfiguration: Codable {
    public var sources: [String] = []
    public var herdrFilter = "all"
    public init() {}
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        sources = try c.decodeIfPresent([String].self, forKey: .sources) ?? []
        herdrFilter = try c.decodeIfPresent(String.self, forKey: .herdrFilter) ?? "all"
    }
}
