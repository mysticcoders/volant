import Foundation

/// macOS settings the launcher flips through System Events: the Light/Dark appearance and the
/// automatically hidden menu bar. Each is one boolean property of System Events, so changing it
/// needs the owner's Automation consent for System Events and nothing else.
public enum SystemToggle: String, CaseIterable, Identifiable, Hashable {
    case appearance, menuBar

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .appearance: return String(localized: "Toggle System Appearance", table: "Core", comment: "System command name: switch macOS between Light and Dark")
        case .menuBar: return String(localized: "Toggle Menu Bar Hiding", table: "Core", comment: "System command name: turn automatic menu bar hiding on or off")
        }
    }

    /// The row's description for the setting's current state, read without Apple Events; nil
    /// when the state is unknown.
    public func detail(on: Bool?) -> String {
        switch (self, on) {
        case (.appearance, true?): return String(localized: "Dark now · switches macOS to Light", table: "Core", comment: "System Appearance row description while macOS is Dark")
        case (.appearance, false?): return String(localized: "Light now · switches macOS to Dark", table: "Core", comment: "System Appearance row description while macOS is Light")
        case (.appearance, nil): return String(localized: "Switch macOS between Light and Dark", table: "Core", comment: "System Appearance row description when the current mode is unknown")
        case (.menuBar, true?): return String(localized: "Hiding automatically now · switches to always shown", table: "Core", comment: "Menu bar row description while the menu bar hides automatically")
        case (.menuBar, false?): return String(localized: "Always shown now · switches to hiding automatically", table: "Core", comment: "Menu bar row description while the menu bar is always shown")
        case (.menuBar, nil): return String(localized: "Hide and show the menu bar automatically", table: "Core", comment: "Menu bar row description when the current setting is unknown")
        }
    }

    /// The footer label for Return, naming what Return will do from the current state.
    public func actionTitle(on: Bool?) -> String {
        switch (self, on) {
        case (.appearance, true?): return String(localized: "Switch to Light", table: "Core", comment: "Footer label for Return on the System Appearance row")
        case (.appearance, false?): return String(localized: "Switch to Dark", table: "Core", comment: "Footer label for Return on the System Appearance row")
        case (.menuBar, true?): return String(localized: "Always Show Menu Bar", table: "Core", comment: "Footer label for Return on the menu bar row")
        case (.menuBar, false?): return String(localized: "Hide Menu Bar Automatically", table: "Core", comment: "Footer label for Return on the menu bar row")
        case (_, nil): return String(localized: "Toggle", table: "Core", comment: "Footer label for Return on a system setting whose state is unknown")
        }
    }

    /// What the launcher reports after a successful change to `on`.
    public func confirmation(on: Bool) -> String {
        switch (self, on) {
        case (.appearance, true): return String(localized: "macOS is now Dark", table: "Core", comment: "Footer feedback after switching macOS to Dark")
        case (.appearance, false): return String(localized: "macOS is now Light", table: "Core", comment: "Footer feedback after switching macOS to Light")
        case (.menuBar, true): return String(localized: "The menu bar now hides automatically", table: "Core", comment: "Footer feedback after turning on automatic menu bar hiding")
        case (.menuBar, false): return String(localized: "The menu bar is now always shown", table: "Core", comment: "Footer feedback after turning off automatic menu bar hiding")
        }
    }

    public var symbol: String {
        switch self {
        case .appearance: return "circle.lefthalf.filled"
        case .menuBar: return "menubar.rectangle"
        }
    }

    private var keywords: [String] {
        switch self {
        case .appearance: return ["dark mode", "light mode", "toggle appearance", "toggle dark mode", "appearance", "system appearance", "night mode"]
        case .menuBar: return ["menu bar", "menubar", "hide menu bar", "show menu bar", "toggle menu bar", "autohide menu bar"]
        }
    }

    /// The System Events property each toggle reads and writes, as four-character codes from
    /// System Events' scripting dictionary: `dark mode` of `appearance preferences`, and
    /// `autohide menu bar` of `dock preferences`.
    public var systemEventsProperty: (container: String, property: String) {
        switch self {
        case .appearance: return ("aprp", "thme")
        case .menuBar: return ("dpas", "dahm")
        }
    }

    /// The global preference that mirrors the setting, read for the row's description only.
    public var globalDefaultsKey: String {
        switch self {
        case .appearance: return "AppleInterfaceStyle"
        case .menuBar: return "_HIHideMenuBar"
        }
    }

    /// Reads the setting from a snapshot of the global preferences domain: Dark is stored as
    /// `AppleInterfaceStyle = Dark` and absent for Light; menu bar hiding as a boolean.
    public func state(inGlobalDefaults defaults: [String: Any]?) -> Bool? {
        guard let defaults else { return nil }
        switch self {
        case .appearance: return (defaults[globalDefaultsKey] as? String)?.caseInsensitiveCompare("Dark") == .orderedSame
        case .menuBar:
            if let value = defaults[globalDefaultsKey] as? Bool { return value }
            if let value = defaults[globalDefaultsKey] as? NSNumber { return value.boolValue }
            return false
        }
    }

    /// Matches from the start of a name or keyword, from three characters, like system actions,
    /// so "dark" finds the toggle but "da" does not fill the list.
    public static func search(_ query: String) -> [SystemToggle] {
        let term = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard term.count >= 3 else { return [] }
        return allCases.filter { toggle in
            ([toggle.title.lowercased()] + toggle.keywords).contains { $0.hasPrefix(term) }
        }
    }
}
