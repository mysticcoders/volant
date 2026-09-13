import Foundation

/// User configuration, read from a JSON file in the app's sandbox container. No settings UI in v0.1.
struct Preferences: Codable {
    var summonHotKey: String = "option+space"
    var notesHotKey: String = "option+n"
    var appHotKeys: [AppHotKey] = []
    var clipboardRetention: Int = 500
    var showOnLaunch: Bool = true
    var help: String = "Edit and choose Reload Config from the menu bar. Hotkey syntax: cmd|ctrl|option|shift + key, e.g. option+space, cmd+shift+t. App hotkeys use the app's bundle identifier."

    enum CodingKeys: String, CodingKey {
        case summonHotKey, notesHotKey, appHotKeys, clipboardRetention, showOnLaunch
        case help = "_help"
    }

    static var supportDirectory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
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

struct AppHotKey: Codable {
    var bundleIdentifier: String
    var hotKey: String
}
