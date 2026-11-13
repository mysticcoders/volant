import Foundation

/// Something a session blocks that the owner can snooze on its own: an app or a website rule.
public enum FocusTarget: Codable, Hashable, Sendable {
    case app(String)
    case website(String)
}

/// One running Focus session. Every change takes the current time, so the app drives it from the
/// real clock and tests from a fixed one. The value is Codable so a session survives relaunch.
public struct FocusSession: Codable, Equatable, Sendable {
    /// Apps a session never hides, whatever the block list says: Volant itself, the Finder and the
    /// system's own login, password and settings windows.
    public static let protectedApps: Set<String> = [
        "com.mysticcoders.volant", "com.mysticcoders.volant.dev", "com.apple.finder", "com.apple.loginwindow",
        "com.apple.SecurityAgent", "com.apple.systempreferences", "com.apple.dock"
    ]

    public struct Snooze: Codable, Equatable, Sendable {
        public let target: FocusTarget
        public let until: Date
    }

    public let id: UUID
    public private(set) var setup: FocusSetup
    public let startedAt: Date
    /// When a timed, running session ends; nil while paused or for a session without a time limit.
    public private(set) var endsAt: Date?
    public private(set) var pausedAt: Date?
    public private(set) var pausedTotal: TimeInterval = 0
    public private(set) var snoozes: [Snooze] = []

    public init(setup: FocusSetup, at now: Date, id: UUID = UUID()) {
        self.id = id
        self.setup = setup
        startedAt = now
        endsAt = setup.minutes.map { now.addingTimeInterval(TimeInterval($0) * 60) }
    }

    public var isPaused: Bool { pausedAt != nil }

    /// Time left, or nil for a session without a time limit. A paused session keeps what it had.
    public func remaining(at now: Date) -> TimeInterval? {
        guard let minutes = setup.minutes else { return nil }
        let end = startedAt.addingTimeInterval(pausedTotal + TimeInterval(minutes) * 60)
        let reference = pausedAt ?? now
        return max(0, end.timeIntervalSince(reference))
    }

    /// Whether a timed session has run out. A paused session never runs out.
    public func isFinished(at now: Date) -> Bool {
        guard let endsAt, pausedAt == nil else { return false }
        return now >= endsAt
    }

    /// Stops the timer and all blocking until `resume`.
    public mutating func pause(at now: Date) {
        guard pausedAt == nil, !isFinished(at: now) else { return }
        pausedAt = now
        endsAt = nil
    }

    /// Restarts the timer with the time that was left when the session was paused.
    public mutating func resume(at now: Date) {
        guard let pausedAt else { return }
        pausedTotal += max(0, now.timeIntervalSince(pausedAt))
        self.pausedAt = nil
        updateEnd()
    }

    /// Replaces the goal, length or block list. A new length counts from the session's start, not
    /// counting time spent paused, so shortening it below the time already spent finishes it.
    public mutating func edit(_ newSetup: FocusSetup, at now: Date) {
        setup = newSetup
        let blocked = Set(newSetup.blockedApps.map(FocusTarget.app) + newSetup.blockedWebsites.map(FocusTarget.website))
        snoozes.removeAll { !blocked.contains($0.target) || $0.until <= now }
        if pausedAt == nil { updateEnd() }
    }

    /// Lets one app or website through for `minutes`, replacing any earlier snooze of it.
    public mutating func snooze(_ target: FocusTarget, minutes: Int, at now: Date) {
        snoozes.removeAll { $0.target == target || $0.until <= now }
        snoozes.append(Snooze(target: target, until: now.addingTimeInterval(TimeInterval(max(1, minutes)) * 60)))
    }

    public func isSnoozed(_ target: FocusTarget, at now: Date) -> Bool {
        snoozes.contains { $0.target == target && $0.until > now }
    }

    /// Whether the app with this bundle identifier should be hidden right now.
    public func blocks(app bundleIdentifier: String, at now: Date) -> Bool {
        guard isBlocking(at: now), !Self.protectedApps.contains(bundleIdentifier),
              setup.blockedApps.contains(bundleIdentifier) else { return false }
        return !isSnoozed(.app(bundleIdentifier), at: now)
    }

    /// The rule that blocks a page address right now, or nil when the page may stay open.
    public func blockingRule(forPageAddress address: String, at now: Date) -> String? {
        guard isBlocking(at: now), let host = FocusHost.host(ofPageAddress: address) else { return nil }
        return setup.blockedWebsites.first { FocusHost.matches(host, rule: $0) && !isSnoozed(.website($0), at: now) }
    }

    /// The earliest moment blocking might change without the owner doing anything: the end of the
    /// session or of a snooze. The app schedules its next check for then.
    public func nextChange(after now: Date) -> Date? {
        guard pausedAt == nil else { return nil }
        return ([endsAt] + snoozes.map(\.until)).compactMap { $0 }.filter { $0 > now }.min()
    }

    private func isBlocking(at now: Date) -> Bool {
        pausedAt == nil && !isFinished(at: now)
    }

    private mutating func updateEnd() {
        endsAt = setup.minutes.map { startedAt.addingTimeInterval(pausedTotal + TimeInterval($0) * 60) }
    }
}
