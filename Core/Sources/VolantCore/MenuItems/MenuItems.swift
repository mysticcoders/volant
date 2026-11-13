import Foundation

/// A menu item's keyboard shortcut as the app reports it: the command character and the
/// Accessibility modifier mask (0 is Command alone; 1 adds Shift, 2 Option, 4 Control, and 8 means
/// no Command). Special keys that an app reports only as a glyph or virtual key are not read, so
/// those items show no shortcut.
public struct MenuShortcut: Codable, Equatable, Hashable {
    public var key: String
    public var modifiers: Int

    public static let shift = 1
    public static let option = 2
    public static let control = 4
    public static let noCommand = 8
    public static let maximumKeyLength = 4

    public init(key: String, modifiers: Int) {
        self.key = key
        self.modifiers = modifiers
    }

    /// A shortcut from the raw attribute values, or nil when the character is missing, too long or
    /// a control character other than the few that have a standard symbol.
    public static func make(character: String?, modifiers: Int?) -> MenuShortcut? {
        guard let character, !character.isEmpty, character.count <= maximumKeyLength else { return nil }
        let mask = (modifiers ?? 0) & (shift | option | control | noCommand)
        if let symbol = symbols[character] { return MenuShortcut(key: symbol, modifiers: mask) }
        guard !character.unicodeScalars.contains(where: { $0.value < 0x20 || $0.value == 0x7F }) else { return nil }
        return MenuShortcut(key: character == " " ? "Space" : character.uppercased(), modifiers: mask)
    }

    private static let symbols: [String: String] = ["\r": "↩", "\u{3}": "⌤", "\u{1B}": "⎋", "\t": "⇥", "\u{8}": "⌫", "\u{7F}": "⌫"]

    /// The shortcut the way macOS menus draw it, such as ⇧⌘E.
    public var display: String {
        var text = ""
        if modifiers & Self.control != 0 { text += "⌃" }
        if modifiers & Self.option != 0 { text += "⌥" }
        if modifiers & Self.shift != 0 { text += "⇧" }
        if modifiers & Self.noCommand == 0 { text += "⌘" }
        return text + key
    }
}

/// One choosable menu item: its titles from the menu bar down, its shortcut and whether the app
/// has it enabled. Items that open a submenu are not listed themselves; their items are.
public struct MenuItem: Codable, Equatable, Hashable, Identifiable {
    public var path: [String]
    public var shortcut: MenuShortcut?
    public var enabled: Bool

    public init(path: [String], shortcut: MenuShortcut? = nil, enabled: Bool = true) {
        self.path = path
        self.shortcut = shortcut
        self.enabled = enabled
    }

    public var id: String { path.joined(separator: "\u{1F}") }
    public var title: String { path.last ?? "" }
    /// The menus that lead to the item, such as “File › Export”.
    public var location: String { path.dropLast().joined(separator: " › ") }
}

/// Why the input helper would not list or press menu items.
public enum MenuRefusal: String, Codable, Equatable, CaseIterable {
    /// Accessibility is not allowed for Volant.
    case notTrusted
    /// Volant itself, the login window, the security agent or another app the helper never reads.
    case excludedApp
    /// The app is no longer the one Volant captured, or it is no longer in front.
    case appChanged
    /// The app has no menu bar the helper can read.
    case noMenuBar
    /// The item is in the Apple menu, which holds system actions such as Shut Down and Log Out.
    case appleMenu
    /// No item has that path any more, or the path leads to a submenu.
    case notFound
    /// The app has the item disabled right now.
    case disabled
    /// The request was malformed or outside the limits in `MenuItemPolicy`.
    case invalidRequest
    /// The app did not perform the press.
    case failed
}

/// The reply to `menuItems`: the items, whether a limit cut the list short, or a refusal.
public struct MenuItemsReply: Codable, Equatable {
    public var items: [MenuItem]
    public var truncated: Bool
    public var refusal: MenuRefusal?

    public init(items: [MenuItem] = [], truncated: Bool = false, refusal: MenuRefusal? = nil) {
        self.items = items
        self.truncated = truncated
        self.refusal = refusal
    }
}

/// The reply to `pressMenuItem`.
public struct MenuPressReply: Codable, Equatable {
    public var pressed: Bool
    public var refusal: MenuRefusal?

    public init(pressed: Bool, refusal: MenuRefusal? = nil) {
        self.pressed = pressed
        self.refusal = refusal
    }
}

/// The bounds and exclusions both sides apply to menu reads and presses.
public enum MenuItemPolicy {
    /// Path components from the menu bar title down: File › Export › Format › PDF at most.
    public static let maximumDepth = 4
    public static let maximumItems = 2000
    /// Longer titles are cut to this many UTF-16 units, the same way on both sides.
    public static let maximumTitleUTF16 = 100
    public static let maximumBundleIDUTF16 = 255
    /// How long one listing may walk an app's menus before it stops and reports a cut list.
    public static let listingBudget: TimeInterval = 3
    /// The largest listing reply the app decodes: every item at the depth and title limits fits.
    public static let maximumReplyBytes = 4 * 1024 * 1024
    /// Processes the helper never reads or presses: Volant and its helpers, the login window and
    /// the security agent that draws password prompts.
    public static let excludedBundleIDs: Set<String> = ["com.apple.loginwindow", "com.apple.SecurityAgent", "com.mysticcoders.volant", "com.mysticcoders.volant.dev"]
    static let excludedPrefixes = ["com.mysticcoders.volant."]

    public static func isExcluded(_ bundleID: String) -> Bool {
        excludedBundleIDs.contains(bundleID) || excludedPrefixes.contains { bundleID.hasPrefix($0) }
    }

    /// A title with control characters removed, trimmed and cut to the limit, or nil when nothing
    /// is left, as for separators.
    public static func title(_ raw: String?) -> String? {
        guard let raw else { return nil }
        let kept = raw.unicodeScalars.filter { !($0.value < 0x20 || $0.value == 0x7F) }
        var text = String(String.UnicodeScalarView(kept)).trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return nil }
        if text.utf16.count > maximumTitleUTF16 {
            text = String(text.utf16.prefix(maximumTitleUTF16)) ?? String(text.prefix(maximumTitleUTF16 / 2))
        }
        return text
    }

    /// A path the helper may resolve: one to `maximumDepth` titles, each already in the form
    /// `title(_:)` produces.
    public static func isValid(path: [String]) -> Bool {
        (1...maximumDepth).contains(path.count) && path.allSatisfy { title($0) == $0 }
    }

    public static func isValid(bundleID: String) -> Bool {
        !bundleID.isEmpty && bundleID.utf16.count <= maximumBundleIDUTF16
            && bundleID.unicodeScalars.allSatisfy { $0.properties.isAlphabetic || CharacterSet(charactersIn: "0123456789.-_").contains($0) }
    }
}

/// The typed words that open Search Menu Items, followed by an optional filter.
public enum MenuItemsQuery {
    /// Longest first, so “menu items export” is not read as the filter “items export”.
    public static let phrases = ["search menu items", "search menus", "menu items", "menus"]

    /// The filter after a phrase, empty for the phrase alone, or nil when the query is something else.
    public static func term(_ query: String) -> String? {
        let text = query.trimmingCharacters(in: .whitespaces)
        let lower = text.lowercased()
        for phrase in phrases {
            if lower == phrase { return "" }
            if lower.hasPrefix(phrase + " ") { return String(text.dropFirst(phrase.count)).trimmingCharacters(in: .whitespaces) }
        }
        return nil
    }
}

/// Orders menu items for a filter: fuzzy on the title, with a smaller weight for the whole path,
/// enabled items before disabled ones, and the menu order for ties and an empty filter.
public enum MenuItemSearch {
    public static let maximumRows = 300

    public static func rank(_ items: [MenuItem], term: String, limit: Int = maximumRows) -> [MenuItem] {
        let filter = term.trimmingCharacters(in: .whitespaces)
        let scored: [(item: MenuItem, score: Int, order: Int)] = items.enumerated().compactMap { order, item in
            guard !filter.isEmpty else { return (item, item.enabled ? 0 : -1, order) }
            let title = FuzzyMatcher.score(query: filter, candidate: item.title).map { $0 + 20 }
            let path = FuzzyMatcher.score(query: filter, candidate: item.path.joined(separator: " "))
            guard let best = [title, path].compactMap({ $0 }).max() else { return nil }
            return (item, best - (item.enabled ? 0 : 10_000), order)
        }
        return scored.sorted { $0.score != $1.score ? $0.score > $1.score : $0.order < $1.order }.prefix(limit).map(\.item)
    }
}

public extension MenuRefusal {
    /// What the launcher says when the helper refused, translated in the Core table.
    var message: String {
        switch self {
        case .notTrusted: return String(localized: "Volant needs Accessibility permission to read menus.", table: "Core", comment: "Search Menu Items message when Accessibility is off for Volant")
        case .excludedApp: return String(localized: "Volant doesn’t read or press the menus of this app.", table: "Core", comment: "Search Menu Items message for Volant itself, the login window or the security agent")
        case .appChanged: return String(localized: "The app in front changed, so Volant didn’t press anything.", table: "Core", comment: "Search Menu Items message when another app came to the front")
        case .noMenuBar: return String(localized: "This app has no menu bar Volant can read.", table: "Core", comment: "Search Menu Items message")
        case .appleMenu: return String(localized: "Volant never presses items in the Apple menu.", table: "Core", comment: "Search Menu Items message; the Apple menu holds Shut Down, Log Out and similar")
        case .notFound: return String(localized: "That menu item changed or is gone, so Volant didn’t press anything.", table: "Core", comment: "Search Menu Items message")
        case .disabled: return String(localized: "That menu item isn’t available right now.", table: "Core", comment: "Search Menu Items message for a disabled item")
        case .invalidRequest: return String(localized: "Volant couldn’t read that menu item.", table: "Core", comment: "Search Menu Items message for a malformed request")
        case .failed: return String(localized: "The app didn’t respond to that menu item.", table: "Core", comment: "Search Menu Items message")
        }
    }
}
