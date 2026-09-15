import Foundation

/// Names that the launcher consumes before checking user shortcuts.
enum LauncherRouting {
    static func isReserved(_ text: String) -> Bool {
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if value.hasPrefix("/") || value.hasPrefix("@") || value.hasPrefix(":") { return true }
        let first = value.split(whereSeparator: \.isWhitespace).first.map(String.init) ?? ""
        return ["caffeinate", "emoji", "wifi", "wi-fi", "bluetooth", "bt", "audio", "input", "output", "vol", "volume", "mute", "unmute", "acp", "settings", "reload", "volant", "notes", "agents", "herdr", "cal", "today", "snip", "ext", "note", "clip"].contains(first)
    }
}
