import AppKit
import Combine
import VolantCore

/// A blocked app or website the owner just tried to reach, shown in the reminder panel.
struct FocusReminder: Identifiable, Equatable {
    let id = UUID()
    let target: FocusTarget
    /// The app's or site's name, as the reminder shows it.
    let name: String
    let goal: String
}

/// Runs the owner's Focus session: keeps its timer, hides blocked apps when they come forward, and
/// saves the session so it survives relaunch. Page addresses are never stored here. The clock,
/// state file and app hiding are injected, so tests drive it without real apps or time.
final class FocusController: ObservableObject {
    @Published private(set) var session: FocusSession?
    /// Ticks once a second while a session runs, so views showing the time left redraw.
    @Published private(set) var now: Date
    @Published private(set) var reminder: FocusReminder?
    @Published private(set) var error: String?
    /// Where the session shows: around the notch, as a floating bar, or as text in the menu bar.
    @Published var placement: FocusBarPlacement {
        didSet { defaults.set(placement.rawValue, forKey: Self.placementKey) }
    }
    /// When a session last completed, so the notch can show it briefly after the session is gone.
    @Published private(set) var completedAt: Date?

    /// Called when a session completes, by time or by the owner, to celebrate it.
    var onComplete: () -> Void = {}

    private let clock: () -> Date
    private let stateURL: URL
    private let defaults: UserDefaults
    private let hide: (NSRunningApplication) -> Bool
    private let frontmost: () -> NSRunningApplication?
    private let automaticTimer: Bool
    private var timer: Timer?
    private var activationObserver: NSObjectProtocol?
    private let browsers: FocusBrowserAccess
    private let browserQueue: DispatchQueue?
    private let frontmostBundle: () -> String?
    /// Tabs Focus blanked, by tab, with the rule that blocked each, so they can be put back. Held in
    /// memory only; a crash loses them and the tabs stay blank.
    private var blankedTabs: [String: (tab: FocusOpenTab, rule: String)] = [:]
    private var browserCheckRunning = false
    /// Browsers whose Automation access the owner refused; Focus stops asking them until relaunch.
    @Published private(set) var refusedBrowsers: Set<String> = []

    static let placementKey = "focusBarPlacement"
    /// The earlier on/off choice for the menu bar, read once so an owner who docked keeps the menu bar.
    static let legacyDockedKey = "focusBarDocked"
    static var defaultStateURL: URL { Preferences.supportDirectory.appendingPathComponent("focus-session.json") }

    init(stateURL: URL = FocusController.defaultStateURL, defaults: UserDefaults = .standard, clock: @escaping () -> Date = Date.init,
         hide: @escaping (NSRunningApplication) -> Bool = { $0.hide() },
         frontmost: @escaping () -> NSRunningApplication? = { NSWorkspace.shared.frontmostApplication },
         automaticTimer: Bool = true, restore: Bool = true,
         browsers: FocusBrowserAccess = AppleEventFocusBrowsers(),
         browserQueue: DispatchQueue? = DispatchQueue(label: "com.mysticcoders.volant.focus-browsers"),
         frontmostBundle: (() -> String?)? = nil) {
        self.browsers = browsers
        self.browserQueue = browserQueue
        self.frontmostBundle = frontmostBundle ?? { frontmost()?.bundleIdentifier }
        self.stateURL = stateURL
        self.defaults = defaults
        self.clock = clock
        self.hide = hide
        self.frontmost = frontmost
        self.automaticTimer = automaticTimer
        now = clock()
        placement = defaults.string(forKey: Self.placementKey).flatMap(FocusBarPlacement.init(rawValue:))
            ?? (defaults.bool(forKey: Self.legacyDockedKey) ? .menuBar : .notch)
        if restore { restoreSavedSession() }
    }

    deinit {
        timer?.invalidate()
        if let activationObserver { NSWorkspace.shared.notificationCenter.removeObserver(activationObserver) }
    }

    var isRunning: Bool { session != nil }

    /// Starts a session, replacing any running one, and hides a blocked app already in front.
    func start(_ setup: FocusSetup) {
        let at = clock()
        session = FocusSession(setup: setup, at: at)
        reminder = nil
        error = nil
        sessionChanged()
        if let app = frontmost() { handleActivation(of: app) }
    }

    func pause() {
        mutate { $0.pause(at: clock()) }
        restoreTabs { _ in true }
    }

    func resume() {
        mutate { $0.resume(at: clock()) }
        if let app = frontmost() { handleActivation(of: app) }
    }

    func edit(_ setup: FocusSetup) {
        mutate { $0.edit(setup, at: clock()) }
        restoreTabs { !setup.blockedWebsites.contains($0) }
        if let app = frontmost() { handleActivation(of: app) }
    }

    /// Ends the session as done and celebrates it.
    func complete() {
        guard session != nil else { return }
        completedAt = clock()
        finish()
        onComplete()
    }

    /// Ends the session without celebrating.
    func end() {
        guard session != nil else { return }
        finish()
    }

    /// Lets the reminder's app or site through for the snooze length and closes the reminder.
    func snooze(_ reminder: FocusReminder, minutes: Int) {
        guard self.reminder?.id == reminder.id else { return }
        mutate { $0.snooze(reminder.target, minutes: minutes, at: clock()) }
        if case .website(let rule) = reminder.target { restoreTabs { $0 == rule } }
        self.reminder = nil
    }

    func dismissReminder() { reminder = nil }

    /// Hides `app` and shows a reminder when the running session blocks it. Never quits the app.
    func handleActivation(of app: NSRunningApplication) {
        guard let bundleIdentifier = app.bundleIdentifier, app.processIdentifier != ProcessInfo.processInfo.processIdentifier else { return }
        if FocusBrowser.named(bundleIdentifier) != nil { checkBrowser() }
        handleActivation(bundleIdentifier: bundleIdentifier, name: app.localizedName) { [hide] in hide(app) }
    }

    /// The decision behind `handleActivation(of:)`, separate from `NSRunningApplication` so tests
    /// can drive it with any bundle identifier.
    func handleActivation(bundleIdentifier: String, name: String?, hideApp: () -> Bool) {
        guard let session, session.blocks(app: bundleIdentifier, at: clock()) else { return }
        _ = hideApp()
        reminder = FocusReminder(target: .app(bundleIdentifier), name: name ?? bundleIdentifier, goal: session.setup.goal)
    }

    /// The time left as the focus bar shows it: `24:59`, `1:05:00`, or nil for an untimed session.
    static func clockText(_ interval: TimeInterval) -> String {
        let total = Int(interval.rounded(.up))
        let hours = total / 3600, minutes = total / 60 % 60, seconds = total % 60
        return hours > 0 ? String(format: "%d:%02d:%02d", hours, minutes, seconds) : String(format: "%d:%02d", minutes, seconds)
    }

    /// The bar's time: what's left, or how long an untimed session has run.
    func timeText() -> String {
        guard let session else { return "" }
        if let remaining = session.remaining(at: now) { return Self.clockText(remaining) }
        return Self.clockText(max(0, now.timeIntervalSince(session.startedAt)))
    }

    /// Advances the clock: finishes an expired session and redraws the time. The timer calls it each
    /// second; tests call it directly.
    func tick() {
        now = clock()
        guard let session else { return }
        if session.isFinished(at: now) { complete(); return }
        checkBrowser()
    }

    /// Asks the browser in front for its current tab and blanks it when the session blocks its
    /// site. Runs at most one check at a time, only while a session is blocking websites, and
    /// drops the answer when the session changed while the browser was answering.
    func checkBrowser() {
        guard !browserCheckRunning, let session, !session.isPaused, !session.isFinished(at: clock()),
              !session.setup.blockedWebsites.isEmpty, let bundle = frontmostBundle(),
              let browser = FocusBrowser.named(bundle), !refusedBrowsers.contains(bundle) else { return }
        browserCheckRunning = true
        let sessionID = session.id
        onBrowserQueue({ [browsers] in Result { try browsers.currentTab(of: browser) } }) { [weak self] result in
            guard let self else { return }
            self.browserCheckRunning = false
            switch result {
            case .failure(let failure):
                if failure as? FocusBrowserFailure == .denied { self.refusedBrowsers.insert(bundle) }
            case .success(let tab):
                guard let tab, let current = self.session, current.id == sessionID,
                      let rule = current.blockingRule(forPageAddress: tab.address, at: self.clock()) else { return }
                self.blank(tab, rule: rule, goal: current.setup.goal)
            }
        }
    }

    /// Replaces the tab with a blank page, remembers its address, and reminds the owner of the goal.
    private func blank(_ tab: FocusOpenTab, rule: String, goal: String) {
        onBrowserQueue({ [browsers] in Result { try browsers.blank(tab) } }) { [weak self] result in
            guard let self, case .success = result else { return }
            if self.blankedTabs[tab.key] == nil { self.blankedTabs[tab.key] = (tab, rule) }
            self.reminder = FocusReminder(target: .website(rule), name: rule, goal: goal)
        }
    }

    /// Puts back the blanked tabs whose rule matches, if they still show the blank page.
    private func restoreTabs(where matches: (String) -> Bool) {
        let restoring = blankedTabs.filter { matches($0.value.rule) }
        guard !restoring.isEmpty else { return }
        for key in restoring.keys { blankedTabs.removeValue(forKey: key) }
        let tabs = restoring.values.map(\.tab)
        onBrowserQueue({ [browsers] in tabs.forEach { _ = try? browsers.restore($0) } }) { _ in }
    }

    /// Runs Apple Events work off the main thread and hands the result back on it; tests pass no
    /// queue and run it in place.
    private func onBrowserQueue<T>(_ work: @escaping () -> T, then finish: @escaping (T) -> Void) {
        guard let browserQueue else { finish(work()); return }
        browserQueue.async {
            let value = work()
            DispatchQueue.main.async { finish(value) }
        }
    }

    private func mutate(_ change: (inout FocusSession) -> Void) {
        guard var current = session else { return }
        change(&current)
        session = current
        sessionChanged()
    }

    private func finish() {
        session = nil
        reminder = nil
        restoreTabs { _ in true }
        sessionChanged()
    }

    /// Saves the session, and starts or stops the timer and the app observer to match it.
    private func sessionChanged() {
        now = clock()
        save()
        if session == nil {
            timer?.invalidate()
            timer = nil
            stopObserving()
        } else {
            startObserving()
            if automaticTimer, timer == nil {
                let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in self?.tick() }
                RunLoop.main.add(timer, forMode: .common)
                self.timer = timer
            }
        }
    }

    private func startObserving() {
        guard activationObserver == nil, automaticTimer else { return }
        activationObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { [weak self] notification in
            guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
            self?.handleActivation(of: app)
        }
    }

    private func stopObserving() {
        if let activationObserver { NSWorkspace.shared.notificationCenter.removeObserver(activationObserver) }
        activationObserver = nil
    }

    /// Writes the running session, or removes the file once none runs. A failed write is shown,
    /// not fatal: the session keeps running in memory.
    private func save() {
        do {
            if let session {
                try JSONEncoder().encode(session).write(to: stateURL, options: .atomic)
            } else if FileManager.default.fileExists(atPath: stateURL.path) {
                try FileManager.default.removeItem(at: stateURL)
            }
            error = nil
        } catch {
            self.error = String(localized: "Volant couldn’t save the Focus session, so it won’t survive a restart.", comment: "Focus error when the session file can't be written")
        }
    }

    /// Picks up a session saved before relaunch, unless it has already run out.
    private func restoreSavedSession() {
        guard let data = try? Data(contentsOf: stateURL), let saved = try? JSONDecoder().decode(FocusSession.self, from: data) else { return }
        if saved.isFinished(at: clock()) {
            try? FileManager.default.removeItem(at: stateURL)
            return
        }
        session = saved
        sessionChanged()
    }
}
