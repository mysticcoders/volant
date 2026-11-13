import AppKit
import SwiftUI
import VolantCore

/// A Focus row in the launcher, for the `focus` query and its words.
enum FocusRow: Hashable {
    /// Opens the setup form.
    case setUp
    /// Starts at once from the remembered setup, with the length and goal typed after `focus`
    /// when given.
    case quickStart(minutes: Int?, goal: String?)
    case pause, resume, complete, edit, end

    var id: String {
        switch self {
        case .setUp: return "set-up"
        case .quickStart(let minutes, let goal): return "start:\(minutes.map(String.init) ?? "-"):\(goal ?? "")"
        case .pause: return "pause"
        case .resume: return "resume"
        case .complete: return "complete"
        case .edit: return "edit"
        case .end: return "end"
        }
    }

    var symbol: String {
        switch self {
        case .setUp, .quickStart: return "target"
        case .pause: return "pause.circle"
        case .resume: return "play.circle"
        case .complete: return "checkmark.circle"
        case .edit: return "slider.horizontal.3"
        case .end: return "stop.circle"
        }
    }

    var title: String {
        switch self {
        case .setUp: return String(localized: "Start Focus Session…", comment: "Focus launcher row: open the setup form")
        case .quickStart(_, let goal?): return String(localized: "Focus on “\(goal, format: .verbatim)”", comment: "Focus launcher row: start now with this goal")
        case .quickStart: return String(localized: "Start with Last Setup", comment: "Focus launcher row: start now with the remembered goal, length and block list")
        case .pause: return String(localized: "Pause Focus Session", comment: "Focus launcher row")
        case .resume: return String(localized: "Resume Focus Session", comment: "Focus launcher row")
        case .complete: return String(localized: "Complete Focus Session", comment: "Focus launcher row: finish the session as done")
        case .edit: return String(localized: "Edit Focus Session…", comment: "Focus launcher row: change the goal, length or block list")
        case .end: return String(localized: "End Focus Session", comment: "Focus launcher row: stop without completing")
        }
    }

    /// The row's subtitle, describing the setup it would start or the session it acts on.
    func detail(remembered: FocusSetup, session: FocusSession?) -> String {
        switch self {
        case .setUp: return String(localized: "Choose a goal, a length and what to block", comment: "Focus launcher row subtitle")
        case .quickStart(let minutes, let goal):
            var setup = remembered
            if let minutes { setup.minutes = minutes }
            if let goal { setup.goal = goal }
            return Self.summary(setup)
        case .pause, .resume, .complete, .edit, .end:
            return session.map { Self.summary($0.setup) } ?? ""
        }
    }

    var primaryAction: String {
        switch self {
        case .setUp, .edit: return String(localized: "Open", comment: "Footer label for Return on a Focus row that opens the form")
        case .quickStart: return String(localized: "Start", comment: "Footer label for Return: start a Focus session")
        case .pause: return String(localized: "Pause", comment: "Footer label for Return: pause the Focus session")
        case .resume: return String(localized: "Resume", comment: "Footer label for Return: resume the Focus session")
        case .complete: return String(localized: "Complete", comment: "Footer label for Return: complete the Focus session")
        case .end: return String(localized: "End", comment: "Footer label for Return: end the Focus session")
        }
    }

    /// `Write the newsletter · 25 min · 14 blocked`, with untitled and untimed sessions named as such.
    static func summary(_ setup: FocusSetup) -> String {
        let goal = setup.goal.isEmpty ? String(localized: "No goal", comment: "Focus summary when the session has no goal") : setup.goal
        let length = setup.minutes.map { String(localized: "\($0, specifier: "%lld") min", comment: "Focus session length in minutes") }
            ?? String(localized: "Until ended", comment: "Focus session without a time limit")
        let count = setup.blockedApps.count + setup.blockedWebsites.count
        let blocked = String(localized: "\(count, specifier: "%lld") blocked", comment: "Focus summary: how many apps and websites the session blocks")
        return [goal, length, blocked].joined(separator: " · ")
    }

    /// The rows for a parsed `focus` query, given whether a session is running.
    static func rows(for command: FocusCommand, session: FocusSession?) -> [FocusRow] {
        guard let session else {
            switch command {
            case .start(let length, let goal):
                let minutes: Int? = if case .minutes(let value) = length { value } else { nil }
                return [.quickStart(minutes: minutes, goal: goal), .setUp]
            default: return [.setUp, .quickStart(minutes: nil, goal: nil)]
            }
        }
        let running: [FocusRow] = [session.isPaused ? .resume : .pause, .complete, .edit, .end]
        switch command {
        case .pause, .resume, .complete, .edit, .end:
            let wanted: FocusRow = switch command {
            case .pause: session.isPaused ? .resume : .pause
            case .resume: session.isPaused ? .resume : .pause
            case .complete: .complete
            case .edit: .edit
            default: .end
            }
            return [wanted] + running.filter { $0 != wanted }
        case .start(let length, let goal):
            let minutes: Int? = if case .minutes(let value) = length { value } else { nil }
            return running + [.quickStart(minutes: minutes, goal: goal)]
        case .menu: return running
        }
    }
}

/// One thing a Focus setup blocks, shown as a removable chip in the form.
enum FocusBlockItem: Hashable, Identifiable {
    case app(bundleIdentifier: String, name: String)
    case website(String)
    case category(FocusCategory)

    var id: String {
        switch self {
        case .app(let id, _): return "app:" + id
        case .website(let host): return "web:" + host
        case .category(let category): return "category:" + category.rawValue
        }
    }

    var title: String {
        switch self {
        case .app(_, let name): return name
        case .website(let host): return host
        case .category(let category): return String(localized: category.title)
        }
    }

    var symbol: String {
        switch self {
        case .app: return "app"
        case .website: return "globe"
        case .category: return "square.grid.2x2"
        }
    }

    /// The chips for a saved setup, with app names looked up from their bundles.
    static func items(for setup: FocusSetup, appName: (String) -> String = FocusBlockItem.appName) -> [FocusBlockItem] {
        setup.categories.map(FocusBlockItem.category) + setup.apps.map { .app(bundleIdentifier: $0, name: appName($0)) } + setup.websites.map(FocusBlockItem.website)
    }

    /// The app's display name, or its bundle identifier when it isn't installed.
    static func appName(_ bundleIdentifier: String) -> String {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier) else { return bundleIdentifier }
        let name = FileManager.default.displayName(atPath: url.path)
        return name.hasSuffix(".app") ? String(name.dropLast(4)) : name
    }
}

/// The setup form's fields, observed by the form alone.
final class FocusDraft: ObservableObject {
    @Published var minutes: Int?
    @Published var blocks: [FocusBlockItem]
    @Published var addText = ""
    /// The settings the remembered setup was read from, so saving it refuses a stale copy.
    var expected: FocusPreferences

    init(setup: FocusSetup, expected: FocusPreferences, appName: (String) -> String = FocusBlockItem.appName) {
        minutes = setup.minutes
        blocks = FocusBlockItem.items(for: setup, appName: appName)
        self.expected = expected
    }

    /// The setup the form describes, with `goal` from the shared name field.
    func setup(goal: String) -> FocusSetup {
        var apps: [String] = [], websites: [String] = [], categories: [FocusCategory] = []
        for block in blocks {
            switch block {
            case .app(let id, _): apps.append(id)
            case .website(let host): websites.append(host)
            case .category(let category): categories.append(category)
            }
        }
        return FocusSetup(goal: goal, minutes: minutes, apps: apps, websites: websites, categories: categories)
    }

    /// What the add field offers for its text: matching categories, installed apps, and the text as
    /// a website when it is one. With no text, the categories not yet added.
    func suggestions(apps search: (String) -> [AppEntry]) -> [FocusBlockItem] {
        let text = addText.trimmingCharacters(in: .whitespacesAndNewlines)
        let added = Set(blocks)
        var out: [FocusBlockItem] = FocusCategory.allCases
            .filter { text.isEmpty || String(localized: $0.title).localizedCaseInsensitiveContains(text) || $0.rawValue.contains(text.lowercased()) }
            .map(FocusBlockItem.category)
        if !text.isEmpty {
            if text.contains("."), let host = FocusHost.rule(from: text) { out.insert(.website(host), at: 0) }
            out += search(text).compactMap { app in
                guard let id = Bundle(url: app.url)?.bundleIdentifier, !FocusSession.protectedApps.contains(id) else { return nil }
                return .app(bundleIdentifier: id, name: app.name)
            }
        }
        return Array(out.filter { !added.contains($0) }.prefix(5))
    }

    func add(_ item: FocusBlockItem) {
        if !blocks.contains(item) { blocks.append(item) }
        addText = ""
    }

    func remove(_ item: FocusBlockItem) {
        blocks.removeAll { $0 == item }
    }
}
