import Foundation

/// What the app observed at one moment: the time, how long since the owner last touched the
/// keyboard or pointer, whether the Mac is asleep or locked, and whether a camera or microphone
/// is in use. The schedule never reads a clock or the system itself.
public struct BreakInput: Equatable, Sendable {
    public var now: Date
    public var idleSeconds: TimeInterval
    /// Asleep, screens asleep, screen locked or another user's session in front.
    public var away: Bool
    /// A camera or microphone is in use, so a break must wait.
    public var inCall: Bool

    public init(now: Date, idleSeconds: TimeInterval = 0, away: Bool = false, inCall: Bool = false) {
        self.now = now
        self.idleSeconds = idleSeconds
        self.away = away
        self.inCall = inCall
    }
}

/// The Break timer: when the next break is due, the heads-up before it, the break itself, and the
/// owner's Postpone, Skip and Pause. Every change takes the current time and the settings, so the
/// app drives it once a second from the real clock and tests drive it from a fixed one. It is
/// Codable so the schedule survives relaunch; it holds only times and counts, never what the owner
/// was doing.
public struct BreakSchedule: Codable, Equatable, Sendable {
    public enum Phase: String, Codable, Sendable {
        /// Counting toward the next break.
        case working
        /// The break is a minute away; the heads-up notice shows.
        case headsUp
        /// The break is due but a camera or microphone is in use.
        case waitingForCall
        /// Gentle strictness: the break is due and the reminder panel asks the owner to start it.
        case reminding
        /// A break is running until `breakEndsAt`.
        case onBreak
    }

    /// Idle stretches shorter than this still count as work in Active Time, such as reading.
    public static let activeIdleLimit: TimeInterval = 120
    /// A longer gap between two observations means the app wasn't running or the Mac slept; the
    /// gap counts as time away.
    public static let missedTickLimit: TimeInterval = 30

    public private(set) var phase: Phase = .working
    /// When the current stretch of work began: the end of the last break, a skip, or turning on.
    public private(set) var cycleStart: Date
    /// Active Time counted since `cycleStart`.
    public private(set) var activeSeconds: TimeInterval = 0
    /// A postponed break isn't due before this.
    public private(set) var postponedUntil: Date?
    /// Breaks are paused until this; nil when they aren't paused.
    public private(set) var pausedUntil: Date?
    public private(set) var breakStartedAt: Date?
    public private(set) var breakEndsAt: Date?
    /// Whether this break paused a Focus session that must be resumed when it ends.
    public var pausedFocusSession = false
    private var lastObserved: Date?
    private var awaySince: Date?

    public init(at now: Date) {
        cycleStart = now
        lastObserved = now
    }

    public var isOnBreak: Bool { phase == .onBreak }

    /// Whether breaks are paused at `now`.
    public func isPaused(at now: Date) -> Bool {
        pausedUntil.map { now < $0 } ?? false
    }

    /// Seconds until the next break is due, counted in active seconds for Active Time and in
    /// wall-clock seconds for Clock Time; zero once due. Nil while breaks are off, paused or a
    /// break is running.
    public func secondsUntilDue(at now: Date, settings: BreakPreferences) -> TimeInterval? {
        guard settings.enabled, !isPaused(at: now), phase != .onBreak else { return nil }
        let postponed = postponedUntil.map { $0.timeIntervalSince(now) } ?? 0
        let scheduled: TimeInterval
        switch settings.mode {
        case .activeTime: scheduled = settings.interval - activeSeconds
        case .clockTime: scheduled = cycleStart.addingTimeInterval(settings.interval).timeIntervalSince(now)
        }
        return max(0, scheduled, postponed)
    }

    /// Seconds left in the running break, or nil when none runs.
    public func breakRemaining(at now: Date) -> TimeInterval? {
        guard phase == .onBreak, let breakEndsAt else { return nil }
        return max(0, breakEndsAt.timeIntervalSince(now))
    }

    /// Whether the app needs to know about cameras and microphones at `now`: only near or past a
    /// due break, or during one, so it doesn't query devices all day.
    public func needsCallState(at now: Date, settings: BreakPreferences) -> Bool {
        if phase != .working { return true }
        guard let due = secondsUntilDue(at: now, settings: settings) else { return false }
        return due <= BreakPreferences.headsUpSeconds + 1
    }

    /// Moves the schedule to `input.now`: counts active time, notices time away, and starts,
    /// defers or ends breaks. The app calls it once a second while breaks are on or one runs.
    public mutating func advance(_ input: BreakInput, settings: BreakPreferences) {
        let now = input.now
        let previous = lastObserved ?? now
        let gap = max(0, now.timeIntervalSince(previous))
        lastObserved = now
        let missed = gap > Self.missedTickLimit ? gap : 0
        if input.away {
            if awaySince == nil { awaySince = min(previous, now) }
        } else {
            awaySince = nil
        }
        var idle: TimeInterval = input.inCall ? 0 : input.idleSeconds
        if let awaySince { idle = max(idle, now.timeIntervalSince(awaySince)) }
        idle = max(idle, missed)

        if phase == .onBreak {
            if let breakEndsAt, now >= breakEndsAt {
                restartCycle(at: now)
            } else if input.inCall {
                clearBreak()
                phase = .waitingForCall
            }
            return
        }
        guard settings.enabled else {
            phase = .working
            return
        }
        if let pausedUntil {
            guard now >= pausedUntil else {
                phase = .working
                return
            }
            restartCycle(at: now)
            return
        }
        let tookBreak = idle >= settings.length
        if tookBreak, settings.mode == .activeTime || phase == .reminding || phase == .waitingForCall {
            restartCycle(at: now)
            return
        }
        if settings.mode == .activeTime, missed == 0, idle < Self.activeIdleLimit, !input.away {
            activeSeconds += gap
        }
        guard let due = secondsUntilDue(at: now, settings: settings) else { return }
        if due <= 0 {
            if tookBreak {
                restartCycle(at: now)
                return
            }
            if input.away { return }
            if input.inCall {
                phase = .waitingForCall
                return
            }
            if phase == .waitingForCall, settings.headsUp {
                postponedUntil = now.addingTimeInterval(BreakPreferences.headsUpSeconds)
                phase = .headsUp
                return
            }
            if settings.strictness == .gentle {
                phase = .reminding
            } else {
                startBreak(at: now, settings: settings)
            }
        } else if settings.headsUp, due <= BreakPreferences.headsUpSeconds, !input.inCall, !input.away {
            phase = .headsUp
        } else {
            phase = .working
        }
    }

    /// Starts a break now, whether or not one is due, for the break length in the settings.
    public mutating func startBreak(at now: Date, settings: BreakPreferences) {
        phase = .onBreak
        postponedUntil = nil
        breakStartedAt = now
        breakEndsAt = now.addingTimeInterval(settings.length)
        lastObserved = now
    }

    /// Moves the due break `minutes` later and ends any running break or reminder. Work time
    /// already counted stays, so the break comes back after the postponement.
    public mutating func postpone(minutes: Int = BreakPreferences.postponeMinutes, at now: Date) {
        clearBreak()
        phase = .working
        postponedUntil = now.addingTimeInterval(TimeInterval(max(1, minutes)) * 60)
    }

    /// Skips the next or running break: the stretch of work starts over without one.
    public mutating func skip(at now: Date) {
        restartCycle(at: now)
    }

    /// Ends a running break early, counting it as taken.
    public mutating func endBreak(at now: Date) {
        guard phase == .onBreak else { return }
        restartCycle(at: now)
    }

    /// Stops breaks until `until`; any running break or reminder ends. Work starts over afterward.
    public mutating func pause(until: Date, at now: Date) {
        restartCycle(at: now)
        pausedUntil = until
    }

    /// Ends a pause early and starts a fresh stretch of work.
    public mutating func resume(at now: Date) {
        pausedUntil = nil
        restartCycle(at: now)
    }

    /// Starts counting from now, as when breaks are turned on or the timing mode changes. A
    /// running break is left alone.
    public mutating func restart(at now: Date) {
        guard phase != .onBreak else { return }
        pausedUntil = nil
        restartCycle(at: now)
    }

    /// Prepares a schedule saved before relaunch. A break that was running counts as taken, so a
    /// restart never covers the screen again; notices are recomputed on the next `advance`.
    public mutating func restored(at now: Date) {
        if phase == .onBreak {
            restartCycle(at: now)
        } else {
            phase = .working
        }
    }

    private mutating func restartCycle(at now: Date) {
        clearBreak()
        phase = .working
        cycleStart = now
        activeSeconds = 0
        postponedUntil = nil
        if let pausedUntil, now >= pausedUntil { self.pausedUntil = nil }
        lastObserved = now
    }

    private mutating func clearBreak() {
        breakStartedAt = nil
        breakEndsAt = nil
    }
}
