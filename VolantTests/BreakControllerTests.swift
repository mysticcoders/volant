import XCTest
import CryptoKit
import VolantCore
@testable import Volant

final class BreakControllerTests: XCTestCase {
    private var root: URL!
    private var now = Date(timeIntervalSince1970: 1_800_000_000)
    private var idle: TimeInterval = 0
    private var call = false
    private var callChecks = 0

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    private var stateURL: URL { root.appendingPathComponent("break-schedule.json") }

    private func controller(_ preferences: BreakPreferences = BreakPreferences(enabled: true), restore: Bool = false) -> BreakController {
        let breaks = BreakController(preferences: preferences, stateURL: stateURL, clock: { [unowned self] in self.now },
                                     idleSeconds: { [unowned self] in self.idle },
                                     inCall: { [unowned self] in self.callChecks += 1; return self.call },
                                     automaticTimer: false, restore: restore)
        breaks.start()
        return breaks
    }

    /// Advances the fake clock one second at a time, ticking the controller each time.
    private func advance(_ breaks: BreakController, seconds: Int) {
        for _ in 0..<seconds {
            now += 1
            breaks.tick()
        }
    }

    func testRunsTheScheduleFromTheInjectedClockAndIdleTime() {
        let breaks = controller()
        advance(breaks, seconds: 44 * 60)
        XCTAssertEqual(breaks.schedule.phase, .headsUp)
        XCTAssertEqual(breaks.statusText(), "Next break in 1 min · active time")
        advance(breaks, seconds: 60)
        XCTAssertTrue(breaks.isOnBreak)
        XCTAssertEqual(breaks.statusText(), "Break ends in 5 min")
        advance(breaks, seconds: 300)
        XCTAssertFalse(breaks.isOnBreak)
        XCTAssertEqual(breaks.statusText(), "Next break in 45 min · active time")
    }

    func testOnlyChecksCamerasAndMicrophonesNearABreak() {
        let breaks = controller()
        advance(breaks, seconds: 30 * 60)
        XCTAssertEqual(callChecks, 0)
        call = true
        advance(breaks, seconds: 16 * 60)
        XCTAssertGreaterThan(callChecks, 0)
        XCTAssertEqual(breaks.schedule.phase, .waitingForCall)
        XCTAssertEqual(breaks.statusText(), "Waiting until the camera and microphone are free")
        call = false
        advance(breaks, seconds: 61)
        XCTAssertTrue(breaks.isOnBreak)
    }

    func testAwayFromSleepOrLockCountsAsABreak() {
        let breaks = controller()
        advance(breaks, seconds: 30 * 60)
        breaks.setAway(.screenLocked, true)
        advance(breaks, seconds: 300)
        breaks.setAway(.screenLocked, false)
        advance(breaks, seconds: 1)
        XCTAssertEqual(breaks.secondsUntilDue() ?? 0, 45 * 60 - 1, accuracy: 1)
    }

    func testIdleTimeComesFromTheInjectedReader() {
        let breaks = controller()
        advance(breaks, seconds: 30 * 60)
        idle = 400
        advance(breaks, seconds: 1)
        XCTAssertEqual(breaks.secondsUntilDue(), 45 * 60)
    }

    func testABreakPausesFocusAndResumesItAfterward() {
        let breaks = controller()
        var focusRunning = true
        var pauses = 0, resumes = 0
        breaks.pauseFocus = { guard focusRunning else { return false }; focusRunning = false; pauses += 1; return true }
        breaks.resumeFocus = { focusRunning = true; resumes += 1 }
        breaks.takeBreakNow()
        XCTAssertEqual(pauses, 1)
        XCTAssertFalse(focusRunning)
        XCTAssertTrue(breaks.schedule.pausedFocusSession)
        advance(breaks, seconds: 10)
        XCTAssertEqual(pauses, 1)
        breaks.endBreak()
        XCTAssertEqual(resumes, 1)
        XCTAssertTrue(focusRunning)
        breaks.takeBreakNow()
        advance(breaks, seconds: 300)
        XCTAssertEqual(resumes, 2, "A break that runs out resumes Focus too")
    }

    func testAFocusSessionTheOwnerPausedStaysPaused() {
        let breaks = controller()
        var resumes = 0
        breaks.pauseFocus = { false }
        breaks.resumeFocus = { resumes += 1 }
        breaks.takeBreakNow()
        breaks.skip()
        XCTAssertEqual(resumes, 0)
    }

    func testPostponeSkipAndPause() {
        let breaks = controller()
        breaks.takeBreakNow()
        breaks.postpone()
        XCTAssertFalse(breaks.isOnBreak)
        XCTAssertEqual(breaks.secondsUntilDue(), 45 * 60)
        breaks.pauseForAnHour()
        XCTAssertTrue(breaks.isPaused)
        XCTAssertNil(breaks.secondsUntilDue())
        XCTAssertTrue(breaks.statusText().hasPrefix("Paused until "))
        breaks.resume()
        XCTAssertFalse(breaks.isPaused)
        advance(breaks, seconds: 600)
        breaks.skip()
        XCTAssertEqual(breaks.secondsUntilDue(), 45 * 60)
    }

    func testTurningOffEndsABreakAndStopsCounting() {
        let breaks = controller()
        breaks.takeBreakNow()
        breaks.apply(BreakPreferences(enabled: false))
        XCTAssertFalse(breaks.isOnBreak)
        XCTAssertNil(breaks.secondsUntilDue())
        XCTAssertEqual(breaks.statusText(), "Off")
        advance(breaks, seconds: 3 * 3600)
        XCTAssertEqual(breaks.schedule.phase, .working)
    }

    func testChangingModeStartsAFreshStretch() {
        let breaks = controller()
        advance(breaks, seconds: 600)
        breaks.apply(BreakPreferences(enabled: true, mode: .clockTime))
        XCTAssertEqual(breaks.secondsUntilDue(), 45 * 60)
        XCTAssertEqual(breaks.statusText(), "Next break in 45 min · clock time")
    }

    func testTheScheduleSurvivesRelaunchButNeverCoversTheScreenAgain() throws {
        var breaks: BreakController? = controller()
        advance(breaks!, seconds: 600)
        breaks?.takeBreakNow()
        XCTAssertTrue(FileManager.default.fileExists(atPath: stateURL.path))
        let saved = try String(contentsOf: stateURL, encoding: .utf8)
        XCTAssertFalse(saved.contains("idle"), "Only times and counts are saved")
        breaks = nil
        now += 5
        let restored = controller(restore: true)
        XCTAssertFalse(restored.isOnBreak)
        XCTAssertEqual(restored.secondsUntilDue(), 45 * 60)
    }

    func testRestoredActiveTimeKeepsCounting() {
        let first = controller()
        advance(first, seconds: 10 * 60)
        first.postpone()
        let restored = controller(restore: true)
        XCTAssertEqual(restored.secondsUntilDue() ?? 0, 35 * 60, accuracy: 1)
    }

    func testSummaryAndClockText() {
        XCTAssertEqual(BreakController.settingsSummary(BreakPreferences()), "Every 45 min of active time · 5-minute breaks")
        XCTAssertEqual(BreakController.settingsSummary(BreakPreferences(mode: .clockTime, intervalMinutes: 60, breakMinutes: 10)), "Every 60 min of clock time · 10-minute breaks")
        XCTAssertEqual(BreakController.clockText(299.2), "5:00")
        XCTAssertEqual(BreakController.clockText(59), "0:59")
        XCTAssertEqual(BreakCopy.suggestion(for: nil), BreakCopy.suggestion(for: nil))
    }

    /// Reads the real idle counter, microphones and cameras once inside the test host, which is the
    /// sandboxed app with Volant's entitlements, to show they answer without a permission prompt.
    /// It only reads; it never opens a device or watches input.
    func testSystemSignalsAnswerInsideTheSandbox() {
        let sandboxed = ProcessInfo.processInfo.environment["APP_SANDBOX_CONTAINER_ID"] != nil
        let idleSeconds = BreakSignals.idleSeconds()
        let microphone = BreakSignals.microphoneInUse()
        let camera = BreakSignals.cameraInUse()
        let microphones = BreakSignals.audioDevices().filter(BreakSignals.hasInputStreams).count
        let cameras = BreakSignals.cameraDevices().count
        print("Break signals: sandboxed=\(sandboxed) idle=\(idleSeconds) microphoneInUse=\(microphone) cameraInUse=\(camera) microphones=\(microphones) cameras=\(cameras)")
        XCTAssertGreaterThanOrEqual(idleSeconds, 0)
        XCTAssertLessThan(idleSeconds, 365 * 24 * 3600)
    }
}

final class BreakRowTests: XCTestCase {
    private func controller(_ preferences: BreakPreferences) -> BreakController {
        BreakController(preferences: preferences, stateURL: FileManager.default.temporaryDirectory.appendingPathComponent("break-\(UUID().uuidString).json"),
                        clock: { Date(timeIntervalSince1970: 1_800_000_000) }, idleSeconds: { 0 }, inCall: { false }, automaticTimer: false, restore: false)
    }

    func testRowsFollowTheState() {
        let off = controller(BreakPreferences())
        XCTAssertEqual(BreakRow.rows(for: .menu, controller: off), [.turnOn, .takeNow])
        XCTAssertEqual(BreakRow.takeNow.detail(controller: off), "A 5-minute break starts now")
        XCTAssertEqual(BreakRow.turnOn.detail(controller: off), "Every 45 min of active time · 5-minute breaks")
        let on = controller(BreakPreferences(enabled: true))
        XCTAssertEqual(BreakRow.rows(for: .menu, controller: on), [.takeNow, .skipNext, .pause, .turnOff])
        XCTAssertEqual(BreakRow.rows(for: .off, controller: on), [.turnOff, .takeNow, .skipNext, .pause])
        XCTAssertEqual(BreakRow.rows(for: .on, controller: on), [.takeNow, .skipNext, .pause, .turnOff], "A row that isn't offered is ignored")
        on.pauseForAnHour()
        XCTAssertEqual(BreakRow.rows(for: .menu, controller: on), [.resume, .takeNow, .turnOff])
        on.takeBreakNow()
        XCTAssertEqual(BreakRow.rows(for: .menu, controller: on), [.endBreak, .turnOff])
    }
}

final class LauncherBreakTests: XCTestCase {
    private var root: URL!
    private var model: LauncherModel!
    private var breaks: BreakController!
    private var config: URL!
    private var reloads = 0

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        config = root.appendingPathComponent("config.json")
        try Data(#"{"future":1,"breaks":{"intervalMinutes":30,"later":"kept"}}"#.utf8).write(to: config)
        let preferences = try JSONDecoder().decode(Preferences.self, from: Data(contentsOf: config))
        breaks = BreakController(preferences: preferences.breaks, stateURL: root.appendingPathComponent("breaks.json"),
                                 idleSeconds: { 0 }, inCall: { false }, automaticTimer: false, restore: false)
        model = LauncherModel(index: AppIndex(entries: []),
                              clipboard: ClipboardStore(retention: 2, storageURL: root.appendingPathComponent("clipboard.sqlite"), encryptionKey: SymmetricKey(size: .bits256)),
                              notes: NotesStore(directory: root.appendingPathComponent("Notes")),
                              config: preferences,
                              usage: UsageStore(url: root.appendingPathComponent("usage.sqlite")), breaks: breaks) { [unowned self] action in
            if case .reloadConfig = action { self.reloads += 1 }
        }
        model.searchesSecondarySources = false
        model.actionConfigURL = config
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    func testTurningOnSavesANarrowPatchAndAppliesIt() throws {
        model.query = "break"
        XCTAssertEqual(model.rows.map(\.id), ["break:on", "break:now"])
        XCTAssertEqual(model.selection, 0)
        model.activateSelection()
        XCTAssertTrue(breaks.preferences.enabled)
        XCTAssertEqual(breaks.preferences.intervalMinutes, 30)
        XCTAssertEqual(reloads, 1)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: config)) as? [String: Any])
        XCTAssertEqual(object["future"] as? Int, 1)
        let block = try XCTUnwrap(object["breaks"] as? [String: Any])
        XCTAssertEqual(block["later"] as? String, "kept")
        XCTAssertEqual(block["enabled"] as? Bool, true)
        XCTAssertEqual(model.rows.map(\.id), ["break:now", "break:skip", "break:pause", "break:off"])
    }

    func testTurningOnRetriesAgainstANewerFile() throws {
        try Data(#"{"breaks":{"intervalMinutes":60}}"#.utf8).write(to: config)
        model.query = "breaks on"
        model.activateSelection()
        XCTAssertTrue(breaks.preferences.enabled)
        XCTAssertEqual(breaks.preferences.intervalMinutes, 60)
        XCTAssertNil(model.actionFeedback)
    }

    func testNewQueriesSelectTheFirstRowAndSameQueryUpdatesKeepIt() {
        breaks.apply(BreakPreferences(enabled: true))
        model.query = "break"
        XCTAssertEqual(model.selection, 0)
        model.selection = 2
        XCTAssertEqual(model.selectedRow?.id, "break:pause")
        model.activateSelection()
        XCTAssertTrue(breaks.isPaused)
        XCTAssertEqual(model.rows.map(\.id), ["break:resume", "break:now", "break:off"])
        XCTAssertEqual(model.selection, 0, "The paused row is gone, so the first row is selected")
        model.query = "break now"
        XCTAssertEqual(model.selectedRow?.id, "break:now")
        model.activateSelection()
        XCTAssertTrue(breaks.isOnBreak)
    }

    func testBreakIsAReservedCoreCommand() {
        XCTAssertTrue(ResultRow.breaks(.takeNow, detail: "").isCoreCommand)
        XCTAssertTrue(LauncherRouting.isReserved("break"))
    }
}
