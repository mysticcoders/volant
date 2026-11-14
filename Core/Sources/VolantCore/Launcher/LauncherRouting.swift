import Foundation

/// Names that the launcher consumes before checking user shortcuts.
public enum LauncherRouting {
    /// Whole queries that open the in-launcher forms for a new snippet or quicklink.
    public static let snippetCreatePhrases: Set<String> = ["new snippet", "create snippet", "add snippet"]
    public static let quicklinkCreatePhrases: Set<String> = ["new quicklink", "create quicklink", "add quicklink"]
    /// Whole queries that open Pick Color, and show the last picked color above it.
    public static let colorPickerPhrases: Set<String> = ["color picker", "pick color", "pick colour", "colour picker"]
    static var createPhrases: Set<String> { snippetCreatePhrases.union(quicklinkCreatePhrases) }

    public static func isReserved(_ text: String) -> Bool {
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if value.hasPrefix("/") || value.hasPrefix("@") || value.hasPrefix(":") { return true }
        if createPhrases.contains(value) || MenuItemsQuery.term(value) != nil { return true }
        if value == "getting started" || value.hasPrefix("getting started ") { return true }
        if ["apple shortcut", "apple shortcuts"].contains(value) || value.hasPrefix("apple shortcut ") || value.hasPrefix("apple shortcuts ") { return true }
        let first = value.split(whereSeparator: \.isWhitespace).first.map(String.init) ?? ""
        return ["shortcuts", "shortcut", "define", "translate", "translation", "translator", "caffeinate", "focus", "break", "breaks", "weather", "emoji", "wifi", "wi-fi", "bluetooth", "bt", "audio", "input", "output", "vol", "volume", "mute", "unmute", "acp", "ai", "talk", "confetti", "settings", "reload", "volant", "notes", "agents", "herdr", "rex", "cal", "today", "snip", "ext", "note", "clip", "catalog", "servers", "server", "ports", "listening", "contacts", "people", "files", "file", "clipboard", "welcome", "onboarding"].contains(first)
    }
}
