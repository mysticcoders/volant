import Foundation

/// User configuration, read from a JSON file in the app's sandbox container. General settings also have a native panel.
struct Preferences: Codable {
    var summonHotKey: String = "option+space"
    var emojiHotKey: String = ""
    var notesHotKey: String = "option+n"
    var appHotKeys: [AppHotKey] = []
    var clipboardRetention: Int = 500
    var showOnLaunch: Bool = true
    var showInDock: Bool = true
    var promotedHarness: String? = nil
    static let harnessOptions: [(id: String, title: String)] = [("all", "All Herdr agents"), ("opencode", "OpenCode"), ("cursor", "Cursor"), ("claude", "Claude Code"), ("codex", "Codex")]
    var snippets: [Snippet] = []
    var quicklinks: [Quicklink] = [Quicklink(name: "Google", url: "https://www.google.com/search?q={query}")]
    var aliases: [String: String] = [:]
    var appearance: Appearance = Appearance()
    var help: String = "Edit and choose Reload Configuration in Settings. Hotkeys: cmd|ctrl|option|shift|meh|hyper + key. App hotkeys use the bundle identifier. Snippets: {date} {isodate} {time} {datetime} {clipboard} {uuid}. Quicklinks: {query}. Aliases map a word to an app name or query. Appearance: scale 0.8–1.4, opacity 0.5–1.0."

    enum CodingKeys: String, CodingKey {
        case summonHotKey, notesHotKey, emojiHotKey, appHotKeys, clipboardRetention, showOnLaunch, showInDock, promotedHarness, snippets, quicklinks, aliases, appearance
        case help = "_help"
    }

    static var supportDirectory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        // Preserve the original storage location across the Volant rebrand.
        let dir = base.appendingPathComponent("Vey", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    static var configURL: URL { supportDirectory.appendingPathComponent("config.json") }

    /// Missing keys fall back to defaults, so a config written by an older version keeps working.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = Preferences()
        summonHotKey = try c.decodeIfPresent(String.self, forKey: .summonHotKey) ?? d.summonHotKey
        notesHotKey = try c.decodeIfPresent(String.self, forKey: .notesHotKey) ?? d.notesHotKey
        emojiHotKey = try c.decodeIfPresent(String.self, forKey: .emojiHotKey) ?? d.emojiHotKey
        appHotKeys = try c.decodeIfPresent([AppHotKey].self, forKey: .appHotKeys) ?? d.appHotKeys
        clipboardRetention = try c.decodeIfPresent(Int.self, forKey: .clipboardRetention) ?? d.clipboardRetention
        showOnLaunch = try c.decodeIfPresent(Bool.self, forKey: .showOnLaunch) ?? d.showOnLaunch
        showInDock = try c.decodeIfPresent(Bool.self, forKey: .showInDock) ?? d.showInDock
        promotedHarness = try c.decodeIfPresent(String.self, forKey: .promotedHarness)
        if let id = promotedHarness, !Self.harnessOptions.contains(where: { $0.id == id }) { promotedHarness = nil }
        snippets = try c.decodeIfPresent([Snippet].self, forKey: .snippets) ?? d.snippets
        quicklinks = try c.decodeIfPresent([Quicklink].self, forKey: .quicklinks) ?? d.quicklinks
        aliases = try c.decodeIfPresent([String: String].self, forKey: .aliases) ?? d.aliases
        appearance = try c.decodeIfPresent(Appearance.self, forKey: .appearance) ?? d.appearance
        help = try c.decodeIfPresent(String.self, forKey: .help) ?? d.help
    }

    init() {}

    /// Patch a single setting, preserving externally edited and unknown configuration fields.
    static func updateBoolean(_ key: String, value: Bool, at url: URL = configURL) throws {
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

    static func updatePromotedHarness(_ harness: String?, at url: URL = configURL) throws {
        guard harness == nil || harnessOptions.contains(where: { $0.id == harness }) else {
            throw CocoaError(.fileReadCorruptFile)
        }
        let data = try Data(contentsOf: url)
        guard var object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw CocoaError(.fileReadCorruptFile)
        }
        object["promotedHarness"] = harness
        let updated = try JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys])
        _ = try JSONDecoder().decode(Preferences.self, from: updated)
        try updated.write(to: url, options: .atomic)
    }

    /// Last load problem, shown in the menu bar. A malformed file is left in place, never replaced.
    static var loadError: String? = nil

    /// Loads the config. Writes the defaults only when no file exists at all.
    static func load() -> Preferences {
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

struct Appearance: Codable, Equatable {
    /// 1.0 is the default 750×480 panel; 0.8 to 1.4 are sensible.
    var scale: Double = 1.0
    /// 1.0 is the system material; lower values let the desktop show through more.
    var opacity: Double = 1.0
}

struct AppHotKey: Codable {
    var bundleIdentifier: String
    var hotKey: String
}
