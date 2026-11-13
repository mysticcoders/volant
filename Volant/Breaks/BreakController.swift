import AppKit
import Combine
import VolantCore

/// Runs the owner's Break schedule: ticks once a second while breaks are on or one runs, reads
/// idle time and camera or microphone use through injected closures, notices sleep and screen
/// lock, saves the schedule so it survives relaunch, and pauses a running Focus session for the
/// length of a break. Only times and counts are saved, never what the owner was doing.
final class BreakController: ObservableObject {
    /// Why the owner is away right now, as the system reported it.
    enum AwayReason: Hashable {
        case systemSleep, screensSleep, screenLocked, sessionInactive
    }

    @Published private(set) var schedule: BreakSchedule
    @Published private(set) var preferences: BreakPreferences
    /// Ticks once a second while breaks run, so views showing a countdown redraw.
    @Published private(set) var now: Date
    @Published private(set) var error: String?

    /// Pauses the running Focus session for a break; returns whether one was paused.
    var pauseFocus: () -> Bool = { false }
    /// Resumes the Focus session a break paused.
    var resumeFocus: () -> Void = {}

    private let clock: () -> Date
    private let idleSeconds: () -> TimeInterval
    private let inCall: () -> Bool
    private let stateURL: URL
    private let automaticTimer: Bool
    private var timer: Timer?
    private var awayReasons = Set<AwayReason>()
    private var observers: [(NotificationCenter, NSObjectProtocol)] = []
    private var lastSaved: Date?

    static let pauseLength: TimeInterval = 3600
    static var defaultStateURL: URL { Preferences.supportDirectory.appendingPathComponent("break-schedule.json") }

    init(preferences: BreakPreferences = BreakPreferences(), stateURL: URL = BreakController.defaultStateURL, clock: @escaping () -> Date = Date.init,
         idleSeconds: @escaping () -> TimeInterval = BreakSignals.idleSeconds, inCall: @escaping () -> Bool = BreakSignals.cameraOrMicrophoneInUse,
         automaticTimer: Bool = true, restore: Bool = true) {
        self.preferences = preferences
        self.stateURL = stateURL
        self.clock = clock
        self.idleSeconds = idleSeconds
        self.inCall = inCall
        self.automaticTimer = automaticTimer
        let at = clock()
        now = at
        var schedule = BreakSchedule(at: at)
        if restore, let data = try? Data(contentsOf: stateURL), let saved = try? JSONDecoder().decode(BreakSchedule.self, from: data) {
            schedule = saved
            schedule.restored(at: at)
        }
        self.schedule = schedule
    }

    /// Starts following the system and the clock, once the Focus hooks are set. A schedule
    /// restored mid-break resumes the Focus session that break paused.
    func start() {
        if automaticTimer, observers.isEmpty { observeSystem() }
        changed(saving: true)
    }

    deinit {
        timer?.invalidate()
        for (center, observer) in observers { center.removeObserver(observer) }
    }

    var isOnBreak: Bool { schedule.isOnBreak }
    var isPaused: Bool { schedule.isPaused(at: now) }

    /// Applies settings from config.json. Turning breaks on, or changing how work is counted,
    /// starts a fresh stretch; turning them off ends a running break.
    func apply(_ updated: BreakPreferences) {
        let previous = preferences
        guard updated != previous else { return }
        preferences = updated
        let at = clock()
        if updated.enabled != previous.enabled || updated.mode != previous.mode {
            if !updated.enabled, schedule.isOnBreak { update { $0.endBreak(at: at) } }
            update { $0.restart(at: at) }
        } else {
            changed(saving: true)
        }
    }

    /// Starts a break now, whether or not breaks are on.
    func takeBreakNow() {
        update { [preferences] in $0.startBreak(at: clock(), settings: preferences) }
    }

    /// Ends the running break early; it counts as taken.
    func endBreak() { update { $0.endBreak(at: clock()) } }

    /// Starts the stretch of work over without a break.
    func skip() { update { $0.skip(at: clock()) } }

    /// Moves the break five minutes later and closes whatever showed it.
    func postpone() { update { $0.postpone(at: clock()) } }

    /// Holds breaks for an hour.
    func pauseForAnHour() {
        let at = clock()
        update { $0.pause(until: at.addingTimeInterval(Self.pauseLength), at: at) }
    }

    func resume() { update { $0.resume(at: clock()) } }

    /// Records that the owner went away or came back for one reason, such as screen lock.
    func setAway(_ reason: AwayReason, _ away: Bool) {
        if away { awayReasons.insert(reason) } else { awayReasons.remove(reason) }
    }

    /// Seconds until the next break, or nil when breaks are off, paused or one runs.
    func secondsUntilDue() -> TimeInterval? {
        schedule.secondsUntilDue(at: now, settings: preferences)
    }

    /// Advances the schedule from the clock and the system's idle and call state. The timer calls
    /// it each second; tests call it directly.
    func tick() {
        let at = clock()
        now = at
        let away = !awayReasons.isEmpty
        let call = !away && schedule.needsCallState(at: at, settings: preferences) && inCall()
        let input = BreakInput(now: at, idleSeconds: away ? 0 : idleSeconds(), away: away, inCall: call)
        let before = schedule
        var next = schedule
        next.advance(input, settings: preferences)
        guard next != before else { return }
        let phaseChanged = next.phase != before.phase || next.cycleStart != before.cycleStart
        schedule = next
        if phaseChanged || lastSaved.map({ at.timeIntervalSince($0) >= 60 }) ?? true {
            changed(saving: true)
        } else {
            syncFocus()
        }
    }

    /// The next break as launcher rows describe it: `Next break in 23 min · active time`.
    func statusText() -> String {
        if let remaining = schedule.breakRemaining(at: now) {
            let minutes = Int((remaining / 60).rounded(.up))
            return String(localized: "Break ends in \(minutes, specifier: "%lld") min", comment: "Breaks status while a break runs")
        }
        if let until = schedule.pausedUntil, isPaused {
            return String(localized: "Paused until \(until.formatted(date: .omitted, time: .shortened), format: .verbatim)", comment: "Breaks status while paused; the value is a time of day")
        }
        guard preferences.enabled else {
            return String(localized: "Off", comment: "Breaks status when breaks are turned off")
        }
        switch schedule.phase {
        case .waitingForCall:
            return String(localized: "Waiting until the camera and microphone are free", comment: "Breaks status while a due break waits for a call to end")
        case .reminding, .onBreak:
            return String(localized: "Break due now", comment: "Breaks status when a break is due")
        case .working, .headsUp:
            let minutes = max(1, Int(((secondsUntilDue() ?? 0) / 60).rounded(.up)))
            switch preferences.mode {
            case .activeTime: return String(localized: "Next break in \(minutes, specifier: "%lld") min · active time", comment: "Breaks status; minutes of active time until the next break")
            case .clockTime: return String(localized: "Next break in \(minutes, specifier: "%lld") min · clock time", comment: "Breaks status; wall-clock minutes until the next break")
            }
        }
    }

    /// The settings in one line: `Every 45 min of active time · 5-minute breaks`.
    static func settingsSummary(_ settings: BreakPreferences) -> String {
        let every: String
        switch settings.mode {
        case .activeTime: every = String(localized: "Every \(settings.intervalMinutes, specifier: "%lld") min of active time", comment: "Breaks settings summary: how often breaks come in Active Time")
        case .clockTime: every = String(localized: "Every \(settings.intervalMinutes, specifier: "%lld") min of clock time", comment: "Breaks settings summary: how often breaks come in Clock Time")
        }
        let length = String(localized: "\(settings.breakMinutes, specifier: "%lld")-minute breaks", comment: "Breaks settings summary: how long each break lasts")
        return [every, length].joined(separator: " · ")
    }

    /// The countdown as the break shows it: `4:59`.
    static func clockText(_ interval: TimeInterval) -> String {
        let total = max(0, Int(interval.rounded(.up)))
        return String(format: "%d:%02d", total / 60, total % 60)
    }

    /// Ends the timer and observers, and resumes a Focus session a break paused, when the app quits.
    func stop() {
        timer?.invalidate()
        timer = nil
        if schedule.isOnBreak { update { $0.endBreak(at: clock()) } }
        for (center, observer) in observers { center.removeObserver(observer) }
        observers = []
    }

    private func update(_ change: (inout BreakSchedule) -> Void) {
        var next = schedule
        change(&next)
        schedule = next
        changed(saving: true)
    }

    /// Saves the schedule, pauses or resumes Focus to match a break, and starts or stops the timer.
    private func changed(saving: Bool) {
        now = clock()
        syncFocus()
        if saving { save() }
        let needsTimer = preferences.enabled || schedule.isOnBreak
        if !needsTimer {
            timer?.invalidate()
            timer = nil
        } else if automaticTimer, timer == nil {
            let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in self?.tick() }
            timer.tolerance = 0.2
            RunLoop.main.add(timer, forMode: .common)
            self.timer = timer
        }
    }

    /// Pauses a running Focus session when a break starts and resumes it when the break is over.
    private func syncFocus() {
        if schedule.isOnBreak, !schedule.pausedFocusSession {
            if pauseFocus() { schedule.pausedFocusSession = true }
        } else if !schedule.isOnBreak, schedule.pausedFocusSession {
            schedule.pausedFocusSession = false
            resumeFocus()
        }
    }

    /// Writes the schedule. A failed write is shown, not fatal: breaks keep running in memory.
    private func save() {
        do {
            try JSONEncoder().encode(schedule).write(to: stateURL, options: .atomic)
            lastSaved = now
            error = nil
        } catch {
            self.error = String(localized: "Volant couldn’t save the break schedule, so it will start over after a restart.", comment: "Breaks error when the schedule file can't be written")
        }
    }

    /// Follows sleep, display sleep, screen lock and fast user switching, which count as time away.
    private func observeSystem() {
        let workspace = NSWorkspace.shared.notificationCenter
        let pairs: [(NotificationCenter, Notification.Name, AwayReason, Bool)] = [
            (workspace, NSWorkspace.willSleepNotification, .systemSleep, true),
            (workspace, NSWorkspace.didWakeNotification, .systemSleep, false),
            (workspace, NSWorkspace.screensDidSleepNotification, .screensSleep, true),
            (workspace, NSWorkspace.screensDidWakeNotification, .screensSleep, false),
            (workspace, NSWorkspace.sessionDidResignActiveNotification, .sessionInactive, true),
            (workspace, NSWorkspace.sessionDidBecomeActiveNotification, .sessionInactive, false),
            (DistributedNotificationCenter.default(), Notification.Name("com.apple.screenIsLocked"), .screenLocked, true),
            (DistributedNotificationCenter.default(), Notification.Name("com.apple.screenIsUnlocked"), .screenLocked, false)
        ]
        for (center, name, reason, away) in pairs {
            let observer = center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                self?.setAway(reason, away)
                self?.tick()
            }
            observers.append((center, observer))
        }
    }
}
