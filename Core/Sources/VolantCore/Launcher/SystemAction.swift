import Foundation

/// Session and power actions. Restart, shut down and log out ask macOS to show its own
/// confirmation dialog rather than acting directly, so unsaved work still gets its chance.
public enum SystemAction: String, CaseIterable, Identifiable, Hashable {
    case lockScreen, sleep, sleepDisplays, screenSaver, restart, shutDown, logOut

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .lockScreen: return "Lock Screen"
        case .sleep: return "Sleep"
        case .sleepDisplays: return "Sleep Displays"
        case .screenSaver: return "Start Screen Saver"
        case .restart: return "Restart…"
        case .shutDown: return "Shut Down…"
        case .logOut: return "Log Out…"
        }
    }

    public var detail: String {
        switch self {
        case .lockScreen: return String(localized: "Lock this Mac now", table: "Core", comment: "System action description in the launcher")
        case .sleep: return String(localized: "Put this Mac to sleep", table: "Core", comment: "System action description in the launcher")
        case .sleepDisplays: return String(localized: "Turn off the displays; locks if a password is required", table: "Core", comment: "System action description in the launcher")
        case .screenSaver: return String(localized: "Start the screen saver", table: "Core", comment: "System action description in the launcher")
        case .restart: return String(localized: "macOS asks before restarting", table: "Core", comment: "System action description in the launcher")
        case .shutDown: return String(localized: "macOS asks before shutting down", table: "Core", comment: "System action description in the launcher")
        case .logOut: return String(localized: "macOS asks before logging out", table: "Core", comment: "System action description in the launcher")
        }
    }

    public var symbol: String {
        switch self {
        case .lockScreen: return "lock"
        case .sleep: return "moon"
        case .sleepDisplays: return "display"
        case .screenSaver: return "sparkles.tv"
        case .restart: return "arrow.clockwise.circle"
        case .shutDown: return "power"
        case .logOut: return "rectangle.portrait.and.arrow.right"
        }
    }

    private var keywords: [String] {
        switch self {
        case .lockScreen: return ["lock", "lock mac", "lock computer"]
        case .sleep: return ["sleep", "sleep mac", "suspend"]
        case .sleepDisplays: return ["display sleep", "screen off", "monitor off", "turn off display"]
        case .screenSaver: return ["screensaver", "screen saver"]
        case .restart: return ["restart", "reboot"]
        case .shutDown: return ["shutdown", "shut down", "power off", "turn off"]
        case .logOut: return ["logout", "log out", "sign out", "log off"]
        }
    }

    /// The loginwindow Apple Event that shows macOS's confirmation for this action, from
    /// AERegistry.h: kAEShowRestartDialog, kAEShowShutdownDialog and kAELogOut.
    public var loginwindowEvent: String? {
        switch self {
        case .restart: return "rrst"
        case .shutDown: return "rsdn"
        case .logOut: return "logo"
        default: return nil
        }
    }

    /// Matches only from the start of a name or keyword, and only from three characters, so
    /// "displays" still finds the Displays settings pane rather than Sleep Displays, and short
    /// searches do not fill the results with power actions.
    public static func search(_ query: String) -> [SystemAction] {
        let term = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard term.count >= 3 else { return [] }
        return allCases.filter { action in
            ([action.title] + action.keywords).contains { $0.lowercased().hasPrefix(term) }
        }
    }
}
