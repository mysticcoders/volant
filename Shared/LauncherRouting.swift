import Foundation

/// Names that the launcher consumes before checking user shortcuts.
enum LauncherRouting {
    static func isReserved(_ text: String) -> Bool {
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if value.hasPrefix("/") || value.hasPrefix("@") || value.hasPrefix(":") { return true }
        let first = value.split(whereSeparator: \.isWhitespace).first.map(String.init) ?? ""
        return ["acp", "agents", "herdr", "cal", "today", "snip", "ext", "note", "clip"].contains(first)
    }
}
