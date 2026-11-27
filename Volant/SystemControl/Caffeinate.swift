import Foundation
import Combine
import IOKit.pwr_mgt

struct CaffeinateCommand: Hashable {
    let minutes: Int? // nil means until stopped
    let display: Bool
    let stop: Bool
    static let off = Self(minutes: nil, display: false, stop: true)
    var id: String { stop ? "off" : "\(minutes.map(String.init) ?? "unlimited"):\(display)" }
    var title: String {
        stop ? String(localized: "Stop Caffeinate", comment: "Launcher row that ends the Caffeinate session")
            : display ? String(localized: "Caffeinate", comment: "Launcher row that keeps the Mac and its display awake")
            : String(localized: "Caffeinate · Display May Sleep", comment: "Launcher row that keeps the Mac awake but lets the display sleep")
    }
    var detail: String {
        stop ? String(localized: "Allow normal idle sleep", comment: "Detail of the Stop Caffeinate row")
            : minutes.map { String(localized: "\($0) minutes", comment: "Caffeinate session length") }
            ?? String(localized: "Until stopped", comment: "Caffeinate session with no time limit")
    }

    static func matches(_ query: String) -> Bool {
        query.lowercased().split(whereSeparator: \.isWhitespace).first == "caffeinate"
    }
    /// Without a modifier, sessions follow the owner's setting, which keeps the display on and unlocked
    /// by default because a dark display that locks reads as sleep. A trailing `display` or `system`
    /// (`mac`) chooses the mode for one session. The bare list offers the default mode first.
    static func parse(_ query: String, keepsDisplayAwake: Bool = true) -> [Self] {
        var words = query.lowercased().split(whereSeparator: \.isWhitespace).map(String.init)
        guard words.first == "caffeinate" else { return [] }
        words.removeFirst()
        if words == ["off"] || words == ["stop"] { return [.off] }
        let modifier = words.last.flatMap { ["display", "system", "mac"].contains($0) ? $0 : nil }
        if modifier != nil { words.removeLast() }
        let display = modifier == nil ? keepsDisplayAwake : modifier == "display"
        if words.isEmpty {
            let modes = modifier == nil ? [keepsDisplayAwake, !keepsDisplayAwake] : [display]
            return modes.flatMap { mode in
                [15, 30, 60].map { Self(minutes: $0, display: mode, stop: false) } + [Self(minutes: nil, display: mode, stop: false)]
            }
        }
        if words == ["on"] { return [Self(minutes: nil, display: display, stop: false)] }
        guard words.count == 1, let token = words.first, let suffix = token.last, ["m", "h"].contains(suffix),
              let amount = Int(token.dropLast()), amount > 0, amount <= (suffix == "h" ? 24 : 1440) else { return [] }
        return [Self(minutes: amount * (suffix == "h" ? 60 : 1), display: display, stop: false)]
    }
}

protocol CaffeinateAssertions {
    func create(display: Bool, timeout: TimeInterval) throws -> UInt32
    func release(_ id: UInt32) throws
}

struct NativeCaffeinateAssertions: CaffeinateAssertions {
    struct Failure: LocalizedError {
        let code: IOReturn
        var errorDescription: String? { String(localized: "macOS couldn’t update Caffeinate (\(code)). Try again.", comment: "The number is an IOKit error code") }
    }
    func create(display: Bool, timeout: TimeInterval) throws -> UInt32 {
        var id: IOPMAssertionID = 0
        // Display-idle prevention also prevents system idle sleep. Timed assertions turn off
        // in macOS even if our run loop stalls; we retain ownership until explicit release.
        let type = display ? kIOPMAssertionTypePreventUserIdleDisplaySleep : kIOPMAssertionTypePreventUserIdleSystemSleep
        let result = IOPMAssertionCreateWithDescription(type as CFString, "Volant Caffeinate" as CFString,
            "Keep awake for your Caffeinate session" as CFString, nil, nil, timeout,
            kIOPMAssertionTimeoutActionTurnOff as CFString, &id)
        guard result == kIOReturnSuccess else { throw Failure(code: result) }
        return id
    }
    func release(_ id: UInt32) throws {
        let result = IOPMAssertionRelease(id)
        guard result == kIOReturnSuccess else { throw Failure(code: result) }
    }
}

/// Main-thread owned session state, with no subprocesses. The only startup assertion is the one the
/// owner asks for with `caffeinateWhileRunning`, applied through `keepAwakeWhileRunning`.
final class CaffeinateService: ObservableObject {
    @Published private(set) var command: CaffeinateCommand?
    @Published private(set) var remaining: Int?
    @Published private(set) var error: String?
    /// Whether the running session is the one the "while Volant runs" setting started.
    @Published private(set) var isAutomatic = false
    private let assertions: CaffeinateAssertions
    private let now: () -> TimeInterval
    private let automaticTimer: Bool
    private var assertion: UInt32?
    private var deadline: TimeInterval?
    private var timer: Timer?
    /// The "while Volant runs" setting as last applied, with its display mode. `paused` is set when the
    /// owner stops Caffeinate by hand, and lasts until the setting is turned on again or Volant relaunches.
    private var settingOn = false
    private var settingDisplay = true
    private var paused = false
    var isActive: Bool { command != nil }
    var summary: String {
        let display = command?.display == true
        if isAutomatic {
            return display ? String(localized: "Mac & display awake · while Volant runs", comment: "Caffeinate status for the session the Settings switch keeps on")
                : String(localized: "Mac awake · display may sleep · while Volant runs", comment: "Caffeinate status for the session the Settings switch keeps on")
        }
        guard let remaining else {
            return display ? String(localized: "Mac & display awake · until stopped", comment: "Caffeinate status")
                : String(localized: "Mac awake · display may sleep · until stopped", comment: "Caffeinate status")
        }
        let time = Duration.seconds(remaining).formatted(.time(pattern: .minuteSecond))
        return display ? String(localized: "Mac & display awake · \(time) remaining", comment: "Caffeinate status; the time is minutes:seconds")
            : String(localized: "Mac awake · display may sleep · \(time) remaining", comment: "Caffeinate status; the time is minutes:seconds")
    }
    init(assertions: CaffeinateAssertions = NativeCaffeinateAssertions(), now: (() -> TimeInterval)? = nil, automaticTimer: Bool = true) {
        self.assertions = assertions
        let clock = ContinuousClock(), start = ContinuousClock.now
        self.now = now ?? { let elapsed = start.duration(to: clock.now).components; return Double(elapsed.seconds) + Double(elapsed.attoseconds) / 1e18 }
        self.automaticTimer = automaticTimer
    }
    /// Applies the "while Volant runs" setting: on starts an until-stopped session in the given display
    /// mode when none is running, and moves the automatic session to a changed mode; off ends the
    /// automatic session but leaves one the owner started. A failure leaves `error` set.
    func keepAwakeWhileRunning(_ enabled: Bool, display: Bool) {
        guard enabled else {
            settingOn = false; paused = false
            if isAutomatic { stop() }
            return
        }
        if !settingOn { settingOn = true; paused = false }
        settingDisplay = display
        if isAutomatic, command?.display != display { stop() }
        startAutomaticIfWanted()
    }

    /// Starts the setting's until-stopped session when the setting is on, not paused, and nothing runs.
    private func startAutomaticIfWanted() {
        guard settingOn, !paused, !isActive else { return }
        isAutomatic = start(CaffeinateCommand(minutes: nil, display: settingDisplay, stop: false))
    }

    /// Starts or stops a session the owner chose. Stopping by hand also pauses the "while Volant runs"
    /// setting until it is turned on again or Volant relaunches.
    @discardableResult func perform(_ next: CaffeinateCommand) -> Bool {
        if next.stop {
            guard stop() else { return false }
            if settingOn { paused = true }
            return true
        }
        return start(next)
    }

    private func start(_ next: CaffeinateCommand) -> Bool {
        if let minutes = next.minutes, !(1...1440).contains(minutes) { error = String(localized: "Choose a duration from 1 minute to 24 hours.", comment: "Caffeinate error"); return false }
        guard !isActive else { error = String(localized: "Stop the current Caffeinate session before starting another."); return false }
        do {
            let seconds = TimeInterval((next.minutes ?? 0) * 60)
            assertion = try assertions.create(display: next.display, timeout: seconds)
            command = next; deadline = next.minutes == nil ? nil : now() + seconds
            remaining = next.minutes.map { $0 * 60 }; error = nil
            if automaticTimer {
                let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in self?.tick() }
                self.timer = timer; RunLoop.main.add(timer, forMode: .common)
            }
            return true
        } catch { self.error = error.localizedDescription; return false }
    }
    func tick() {
        guard let deadline else { return }
        remaining = max(0, Int(ceil(deadline - now())))
        if remaining == 0 { _ = stop(); startAutomaticIfWanted() }
    }
    @discardableResult func stop() -> Bool {
        if let assertion {
            do { try assertions.release(assertion) }
            catch { self.error = error.localizedDescription; return false }
        }
        assertion = nil; command = nil; deadline = nil; remaining = nil; isAutomatic = false
        timer?.invalidate(); timer = nil; error = nil
        return true
    }
    deinit { timer?.invalidate(); if let assertion { try? assertions.release(assertion) } }
}
