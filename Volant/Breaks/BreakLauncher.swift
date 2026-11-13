import Foundation
import VolantCore

/// A Break row in the launcher, for the `break` and `breaks` queries.
enum BreakRow: String, Hashable, CaseIterable {
    case takeNow = "now"
    case endBreak = "end"
    case skipNext = "skip"
    case pause
    case resume
    case turnOn = "on"
    case turnOff = "off"

    var id: String { rawValue }

    var symbol: String {
        switch self {
        case .takeNow: return "figure.walk"
        case .endBreak: return "stop.circle"
        case .skipNext: return "forward.end"
        case .pause: return "pause.circle"
        case .resume: return "play.circle"
        case .turnOn: return "bell"
        case .turnOff: return "bell.slash"
        }
    }

    var title: String {
        switch self {
        case .takeNow: return String(localized: "Take a Break Now", comment: "Breaks launcher row")
        case .endBreak: return String(localized: "End Break", comment: "Breaks button: end the running break early")
        case .skipNext: return String(localized: "Skip Next Break", comment: "Breaks launcher row")
        case .pause: return String(localized: "Pause Breaks for 1 Hour", comment: "Breaks launcher row")
        case .resume: return String(localized: "Resume Breaks", comment: "Breaks launcher row: end a pause early")
        case .turnOn: return String(localized: "Turn On Breaks", comment: "Breaks launcher row")
        case .turnOff: return String(localized: "Turn Off Breaks", comment: "Breaks launcher row")
        }
    }

    var primaryAction: String {
        switch self {
        case .takeNow: return String(localized: "Start Break", comment: "Gentle break reminder button: start the break now")
        case .endBreak: return String(localized: "End Break", comment: "Breaks button: end the running break early")
        case .skipNext: return String(localized: "Skip", comment: "Breaks button: skip this break")
        case .pause: return String(localized: "Pause", comment: "Footer label for Return: pause breaks")
        case .resume: return String(localized: "Resume", comment: "Footer label for Return: resume breaks")
        case .turnOn: return String(localized: "Turn On", comment: "Footer label for Return: turn breaks on")
        case .turnOff: return String(localized: "Turn Off", comment: "Footer label for Return: turn breaks off")
        }
    }

    /// The row's subtitle: the settings it would turn on, the length of a break taken now, or
    /// when the next break is.
    func detail(controller: BreakController) -> String {
        switch self {
        case .turnOn: return BreakController.settingsSummary(controller.preferences)
        case .takeNow where !controller.preferences.enabled:
            return String(localized: "A \(controller.preferences.breakMinutes, specifier: "%lld")-minute break starts now", comment: "Breaks launcher row subtitle while breaks are off")
        default: return controller.statusText()
        }
    }

    /// The rows for a parsed query given the controller's state. A command that names a row puts it
    /// first; the others keep their usual order after it.
    static func rows(for command: BreakCommand, controller: BreakController) -> [BreakRow] {
        let available: [BreakRow]
        if controller.isOnBreak {
            available = [.endBreak, .turnOff]
        } else if !controller.preferences.enabled {
            available = [.turnOn, .takeNow]
        } else if controller.isPaused {
            available = [.resume, .takeNow, .turnOff]
        } else {
            available = [.takeNow, .skipNext, .pause, .turnOff]
        }
        let wanted: BreakRow? = switch command {
        case .menu: nil
        case .now: .takeNow
        case .skip: .skipNext
        case .pause: .pause
        case .resume: .resume
        case .on: .turnOn
        case .off: .turnOff
        case .end: .endBreak
        }
        guard let wanted, available.contains(wanted) else { return available }
        return [wanted] + available.filter { $0 != wanted }
    }
}
