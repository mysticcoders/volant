import Foundation

/// User configuration, read from a JSON file in the app's sandbox container. No settings UI in v0.1.
struct Preferences: Codable {
    var summonHotKey: String = "option+space"
    var notesHotKey: String = "option+n"
    var appHotKeys: [AppHotKey] = []
    var clipboardRetention: Int = 500
    var showOnLaunch: Bool = true
    var snippets: [Snippet] = []
    var quicklinks: [Quicklink] = [Quicklink(name: "Google", url: "https://www.google.com/search?q={query}")]
    var aliases: [String: String] = [:]
    var appearance: Appearance = Appearance()
    var help: String = "Edit and choose Reload Config from the menu bar. Hotkeys: cmd|ctrl|option|shift|meh|hyper + key. App hotkeys use the bundle identifier. Snippets: {date} {isodate} {time} {datetime} {clipboard} {uuid}. Quicklinks: {query}. Aliases map a word to an app name or query. Appearance: scale 0.8–1.4, opacity 0.5–1.0."

    enum CodingKeys: String, CodingKey {
        case summonHotKey, notesHotKey, appHotKeys, clipboardRetention, showOnLaunch, snippets, quicklinks, aliases, appearance
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
        appHotKeys = try c.decodeIfPresent([AppHotKey].self, forKey: .appHotKeys) ?? d.appHotKeys
        clipboardRetention = try c.decodeIfPresent(Int.self, forKey: .clipboardRetention) ?? d.clipboardRetention
        showOnLaunch = try c.decodeIfPresent(Bool.self, forKey: .showOnLaunch) ?? d.showOnLaunch
        snippets = try c.decodeIfPresent([Snippet].self, forKey: .snippets) ?? d.snippets
        quicklinks = try c.decodeIfPresent([Quicklink].self, forKey: .quicklinks) ?? d.quicklinks
        aliases = try c.decodeIfPresent([String: String].self, forKey: .aliases) ?? d.aliases
        appearance = try c.decodeIfPresent(Appearance.self, forKey: .appearance) ?? d.appearance
        help = try c.decodeIfPresent(String.self, forKey: .help) ?? d.help
    }

    init() {}

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
