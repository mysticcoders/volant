import Foundation

/// What the first launch does about the Welcome window. Decided once per launch from whether the
/// configuration file existed before Volant read it and from its `welcomeCompleted` value.
public enum WelcomeLaunch: Equatable {
    /// Show the Welcome window instead of the launcher.
    case show
    /// An install from before the Welcome window existed: record it as done and never show it.
    case markDone
    /// Already seen on this Mac.
    case skip

    /// A fresh install writes `welcomeCompleted: false` when it decides to show the window, so a
    /// Welcome closed by a crash or a forced quit shows again; a file without the key that was already
    /// there is an older install, which never sees it.
    public static func decide(configExisted: Bool, completed: Bool?) -> WelcomeLaunch {
        switch completed {
        case true?: return .skip
        case false?: return .show
        case nil: return configExisted ? .markDone : .show
        }
    }
}

/// The Welcome window's pages, in order. The agents page appears only when something is installed.
public enum WelcomeStep: String, CaseIterable, Identifiable, Sendable {
    case shortcut, typing, access, agents, extensions
    public var id: String { rawValue }

    /// The pages to show, leaving out the agents page when no agent or terminal was found.
    public static func steps(showingAgents: Bool) -> [WelcomeStep] {
        allCases.filter { $0 != .agents || showingAgents }
    }

    /// The page after `step`, or nil on the last page.
    public static func next(after step: WelcomeStep, showingAgents: Bool) -> WelcomeStep? {
        let steps = steps(showingAgents: showingAgents)
        guard let index = steps.firstIndex(of: step) else { return steps.first }
        return steps.indices.contains(index + 1) ? steps[index + 1] : nil
    }

    /// The page before `step`, or nil on the first page.
    public static func previous(before step: WelcomeStep, showingAgents: Bool) -> WelcomeStep? {
        let steps = steps(showingAgents: showingAgents)
        guard let index = steps.firstIndex(of: step), index > 0 else { return nil }
        return steps[index - 1]
    }
}

/// One line of the Welcome window's "What you can type" page: what to type, what it does, and the text
/// Try It puts in the launcher's search field.
public struct WelcomeTip: Identifiable, Equatable, Sendable {
    public let id: String
    public let typed: String
    public let symbol: String
    public let tryQuery: String
    public let detailResource: LocalizedStringResource

    public var detail: String { String(localized: detailResource) }

    public static func == (lhs: WelcomeTip, rhs: WelcomeTip) -> Bool { lhs.id == rhs.id }

    /// The typed forms, each with the word form beside its one-character shortcut where both exist.
    /// Typed text is English launcher syntax and is never translated.
    public static let all: [WelcomeTip] = [
        WelcomeTip(id: "contacts", typed: "@jane · contacts", symbol: "person.crop.circle", tryQuery: "contacts",
                   detailResource: LocalizedStringResource("Search your contacts", table: "Core", comment: "Welcome window: what typing @ or contacts does")),
        WelcomeTip(id: "files", typed: "/report · files", symbol: "doc.text.magnifyingglass", tryQuery: "files",
                   detailResource: LocalizedStringResource("Find files by name", table: "Core", comment: "Welcome window: what typing / or files does")),
        WelcomeTip(id: "clipboard", typed: "clip · clipboard", symbol: "doc.on.clipboard", tryQuery: "clipboard",
                   detailResource: LocalizedStringResource("Find something you copied", table: "Core", comment: "Welcome window: what typing clip or clipboard does")),
        WelcomeTip(id: "emoji", typed: ":smile", symbol: "face.smiling", tryQuery: ":",
                   detailResource: LocalizedStringResource("Pick an emoji", table: "Core", comment: "Welcome window: what typing a colon does")),
        WelcomeTip(id: "calendar", typed: "cal · today", symbol: "calendar", tryQuery: "today",
                   detailResource: LocalizedStringResource("See what’s on your calendar", table: "Core", comment: "Welcome window: what typing cal or today does")),
        WelcomeTip(id: "notes", typed: "notes", symbol: "note.text", tryQuery: "notes",
                   detailResource: LocalizedStringResource("Write and find Markdown notes", table: "Core", comment: "Welcome window: what typing notes does")),
        WelcomeTip(id: "translate", typed: "translate", symbol: "character.bubble", tryQuery: "translate",
                   detailResource: LocalizedStringResource("Translate text on your Mac", table: "Core", comment: "Welcome window: what typing translate does")),
        WelcomeTip(id: "define", typed: "define word", symbol: "book.closed", tryQuery: "define ",
                   detailResource: LocalizedStringResource("Look a word up in your dictionaries", table: "Core", comment: "Welcome window: what typing define does")),
        WelcomeTip(id: "talk", typed: "talk", symbol: "mic", tryQuery: "talk",
                   detailResource: LocalizedStringResource("Dictate text (macOS 26 and later)", table: "Core", comment: "Welcome window: what typing talk does")),
        WelcomeTip(id: "agents", typed: "ai · agents · rex", symbol: "bubble.left.and.bubble.right", tryQuery: "ai",
                   detailResource: LocalizedStringResource("Chat with an agent, or see your agent terminals", table: "Core", comment: "Welcome window: what typing ai, agents or rex does")),
        WelcomeTip(id: "extensions", typed: "ext", symbol: "puzzlepiece.extension", tryQuery: "ext ",
                   detailResource: LocalizedStringResource("Run your extensions", table: "Core", comment: "Welcome window: what typing ext does")),
        WelcomeTip(id: "servers", typed: "servers", symbol: "server.rack", tryQuery: "servers",
                   detailResource: LocalizedStringResource("See local servers that are listening", table: "Core", comment: "Welcome window: what typing servers does")),
        WelcomeTip(id: "weather", typed: "weather · weather tokyo", symbol: "cloud.sun", tryQuery: "weather",
                   detailResource: LocalizedStringResource("See the forecast here or anywhere", table: "Core", comment: "Welcome window: what typing weather does")),
        WelcomeTip(id: "focus", typed: "focus 25m write", symbol: "target", tryQuery: "focus",
                   detailResource: LocalizedStringResource("Block distracting apps and websites", table: "Core", comment: "Welcome window: what typing focus does")),
        WelcomeTip(id: "breaks", typed: "breaks", symbol: "figure.walk", tryQuery: "breaks",
                   detailResource: LocalizedStringResource("Get reminded to step away", table: "Core", comment: "Welcome window: what typing breaks does"))
    ]
}

/// Other launchers whose usual shortcut is Option-Space or Command-Space, so the Welcome window can
/// mention them by name when they are running. Checked only by bundle identifier; nothing is started.
public enum WelcomeCompetingLaunchers {
    public static let bundleIdentifiers: [String: String] = [
        "com.raycast.macos": "Raycast",
        "com.runningwithcrayons.Alfred": "Alfred",
        "com.runningwithcrayons.Alfred-3": "Alfred"
    ]

    /// The names of the launchers among `running` bundle identifiers, sorted and without duplicates.
    public static func names(running: [String]) -> [String] {
        Array(Set(running.compactMap { bundleIdentifiers[$0] })).sorted()
    }
}
