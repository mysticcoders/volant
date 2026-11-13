import XCTest

@testable import VolantCore

final class BreakPreferencesTests: XCTestCase {
    func testDefaultsAreOffActiveTimeAndStandard() {
        let settings = BreakPreferences()
        XCTAssertFalse(settings.enabled)
        XCTAssertEqual(settings.mode, .activeTime)
        XCTAssertEqual(settings.intervalMinutes, 45)
        XCTAssertEqual(settings.breakMinutes, 5)
        XCTAssertEqual(settings.strictness, .standard)
        XCTAssertTrue(settings.headsUp)
        XCTAssertFalse(Preferences().breaks.enabled)
    }

    func testDecodingClampsAndDropsUnknownValues() throws {
        let json = #"{"enabled":true,"mode":"lunar","intervalMinutes":2,"breakMinutes":90,"strictness":"brutal","future":1}"#
        let settings = try JSONDecoder().decode(BreakPreferences.self, from: Data(json.utf8))
        XCTAssertTrue(settings.enabled)
        XCTAssertEqual(settings.mode, .activeTime)
        XCTAssertEqual(settings.intervalMinutes, 10)
        XCTAssertEqual(settings.breakMinutes, 30)
        XCTAssertEqual(settings.strictness, .standard)
        XCTAssertTrue(settings.headsUp)
        let wrongTypes = try JSONDecoder().decode(BreakPreferences.self, from: Data(#"{"enabled":"yes","intervalMinutes":"many","mode":"clock"}"#.utf8))
        XCTAssertFalse(wrongTypes.enabled)
        XCTAssertEqual(wrongTypes.intervalMinutes, 45)
        XCTAssertEqual(wrongTypes.mode, .clockTime)
    }

    func testUpdateKeepsUnknownKeysAndRefusesStaleCopies() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".json")
        defer { try? FileManager.default.removeItem(at: url) }
        try Data(#"{"future":1,"breaks":{"intervalMinutes":30,"later":"kept"}}"#.utf8).write(to: url)
        let loaded = try JSONDecoder().decode(Preferences.self, from: Data(contentsOf: url))
        XCTAssertEqual(loaded.breaks.intervalMinutes, 30)
        var updated = loaded.breaks
        updated.enabled = true
        updated.strictness = .strict
        try Preferences.updateBreaks(updated, expected: loaded.breaks, at: url)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        XCTAssertEqual(object["future"] as? Int, 1)
        let block = try XCTUnwrap(object["breaks"] as? [String: Any])
        XCTAssertEqual(block["later"] as? String, "kept")
        XCTAssertEqual(block["strictness"] as? String, "strict")
        XCTAssertEqual(block["mode"] as? String, "active")
        XCTAssertThrowsError(try Preferences.updateBreaks(BreakPreferences(), expected: loaded.breaks, at: url))
        XCTAssertTrue(try JSONDecoder().decode(Preferences.self, from: Data(contentsOf: url)).breaks.enabled)
    }

    func testBreaksAreNotSynced() {
        XCTAssertFalse(SettingsSync.keys.contains("breaks"))
    }

    func testOnlyStrictAndStandardCoverTheScreen() {
        XCTAssertFalse(BreakStrictness.gentle.coversScreen)
        XCTAssertTrue(BreakStrictness.standard.coversScreen)
        XCTAssertTrue(BreakStrictness.strict.coversScreen)
    }
}

final class BreakCommandTests: XCTestCase {
    func testParsesBreakQueries() {
        XCTAssertEqual(BreakCommand.parse("break"), .menu)
        XCTAssertEqual(BreakCommand.parse("Breaks "), .menu)
        XCTAssertEqual(BreakCommand.parse("break now"), .now)
        XCTAssertEqual(BreakCommand.parse("break SKIP"), .skip)
        XCTAssertEqual(BreakCommand.parse("breaks pause"), .pause)
        XCTAssertEqual(BreakCommand.parse("breaks resume"), .resume)
        XCTAssertEqual(BreakCommand.parse("breaks on"), .on)
        XCTAssertEqual(BreakCommand.parse("breaks off"), .off)
        XCTAssertEqual(BreakCommand.parse("break end"), .end)
        XCTAssertEqual(BreakCommand.parse("break something else"), .menu)
        XCTAssertNil(BreakCommand.parse("breakfast"))
        XCTAssertNil(BreakCommand.parse("focus"))
        XCTAssertNil(BreakCommand.parse(""))
    }

    func testBreakWordsAreReservedLauncherCommands() {
        XCTAssertTrue(LauncherRouting.isReserved("break"))
        XCTAssertTrue(LauncherRouting.isReserved("breaks"))
        XCTAssertFalse(LauncherRouting.isReserved("breakfast"))
        XCTAssertEqual(CoreCommand.breaks.query, "breaks")
    }
}

final class BreakScheduleTests: XCTestCase {
    private let start = Date(timeIntervalSince1970: 1_800_000_000)
    private var settings = BreakPreferences(enabled: true)

    /// Advances the schedule second by second for `seconds`, with the same observation each time.
    private func run(_ schedule: inout BreakSchedule, from: inout Date, seconds: Int, idle: (Int) -> TimeInterval = { _ in 0 },
                     away: Bool = false, inCall: Bool = false) {
        for second in 1...seconds {
            from += 1
            schedule.advance(BreakInput(now: from, idleSeconds: idle(second), away: away, inCall: inCall), settings: settings)
        }
    }

    func testActiveTimeCountsOnlyWhileTheOwnerIsThere() {
        var schedule = BreakSchedule(at: start)
        var now = start
        run(&schedule, from: &now, seconds: 600)
        XCTAssertEqual(schedule.secondsUntilDue(at: now, settings: settings), 35 * 60)
        run(&schedule, from: &now, seconds: 200, idle: { TimeInterval($0) })
        XCTAssertEqual(schedule.activeSeconds, 600 + 119, accuracy: 0.5)
        run(&schedule, from: &now, seconds: 10)
        XCTAssertEqual(schedule.activeSeconds, 729, accuracy: 0.5)
    }

    func testBeingAwayForTheBreakLengthCountsAsABreak() {
        var schedule = BreakSchedule(at: start)
        var now = start
        run(&schedule, from: &now, seconds: 30 * 60)
        run(&schedule, from: &now, seconds: 300, idle: { TimeInterval($0) })
        XCTAssertEqual(schedule.activeSeconds, 0)
        XCTAssertEqual(schedule.cycleStart, now)
        XCTAssertEqual(schedule.secondsUntilDue(at: now, settings: settings), 45 * 60)
    }

    func testHeadsUpComesAMinuteBeforeAndThenTheBreak() {
        var schedule = BreakSchedule(at: start)
        var now = start
        run(&schedule, from: &now, seconds: 44 * 60 - 1)
        XCTAssertEqual(schedule.phase, .working)
        run(&schedule, from: &now, seconds: 1)
        XCTAssertEqual(schedule.phase, .headsUp)
        run(&schedule, from: &now, seconds: 60)
        XCTAssertEqual(schedule.phase, .onBreak)
        XCTAssertEqual(schedule.breakStartedAt, now)
        XCTAssertEqual(schedule.breakRemaining(at: now), 300)
        XCTAssertNil(schedule.secondsUntilDue(at: now, settings: settings))
    }

    func testWithoutHeadsUpTheBreakStartsDirectly() {
        settings.headsUp = false
        var schedule = BreakSchedule(at: start)
        var now = start
        run(&schedule, from: &now, seconds: 45 * 60 - 1)
        XCTAssertEqual(schedule.phase, .working)
        run(&schedule, from: &now, seconds: 1)
        XCTAssertEqual(schedule.phase, .onBreak)
    }

    func testABreakEndsOnTimeAndStartsANewStretch() {
        var schedule = BreakSchedule(at: start)
        var now = start
        schedule.startBreak(at: now, settings: settings)
        run(&schedule, from: &now, seconds: 299, idle: { TimeInterval($0) })
        XCTAssertTrue(schedule.isOnBreak)
        run(&schedule, from: &now, seconds: 1, idle: { _ in 300 })
        XCTAssertEqual(schedule.phase, .working)
        XCTAssertEqual(schedule.cycleStart, now)
        XCTAssertNil(schedule.breakEndsAt)
    }

    func testGentleStrictnessRemindsInsteadOfStarting() {
        settings.strictness = .gentle
        settings.headsUp = false
        var schedule = BreakSchedule(at: start)
        var now = start
        run(&schedule, from: &now, seconds: 45 * 60)
        XCTAssertEqual(schedule.phase, .reminding)
        run(&schedule, from: &now, seconds: 120)
        XCTAssertEqual(schedule.phase, .reminding)
        schedule.startBreak(at: now, settings: settings)
        XCTAssertEqual(schedule.phase, .onBreak)
    }

    func testGentleReminderIgnoredWhileAwayCountsAsTaken() {
        settings.strictness = .gentle
        settings.mode = .clockTime
        settings.headsUp = false
        var schedule = BreakSchedule(at: start)
        var now = start
        run(&schedule, from: &now, seconds: 45 * 60)
        XCTAssertEqual(schedule.phase, .reminding)
        run(&schedule, from: &now, seconds: 300, idle: { TimeInterval($0) })
        XCTAssertEqual(schedule.phase, .working)
        XCTAssertEqual(schedule.cycleStart, now)
    }

    func testPostponeMovesTheBreakFiveMinutesAndKeepsCountedWork() {
        var schedule = BreakSchedule(at: start)
        var now = start
        run(&schedule, from: &now, seconds: 45 * 60)
        XCTAssertEqual(schedule.phase, .onBreak)
        schedule.postpone(at: now)
        XCTAssertEqual(schedule.phase, .working)
        XCTAssertEqual(schedule.secondsUntilDue(at: now, settings: settings), 300)
        run(&schedule, from: &now, seconds: 240)
        XCTAssertEqual(schedule.phase, .headsUp)
        run(&schedule, from: &now, seconds: 60)
        XCTAssertEqual(schedule.phase, .onBreak)
    }

    func testPostponeFromTheHeadsUp() {
        var schedule = BreakSchedule(at: start)
        var now = start
        run(&schedule, from: &now, seconds: 44 * 60 + 10)
        XCTAssertEqual(schedule.phase, .headsUp)
        schedule.postpone(at: now)
        XCTAssertEqual(schedule.phase, .working)
        run(&schedule, from: &now, seconds: 60)
        XCTAssertEqual(schedule.phase, .working)
    }

    func testSkipStartsTheStretchOverWithoutABreak() {
        var schedule = BreakSchedule(at: start)
        var now = start
        run(&schedule, from: &now, seconds: 44 * 60 + 30)
        XCTAssertEqual(schedule.phase, .headsUp)
        schedule.skip(at: now)
        XCTAssertEqual(schedule.phase, .working)
        XCTAssertEqual(schedule.activeSeconds, 0)
        XCTAssertEqual(schedule.secondsUntilDue(at: now, settings: settings), 45 * 60)
        schedule.startBreak(at: now, settings: settings)
        schedule.skip(at: now)
        XCTAssertFalse(schedule.isOnBreak)
    }

    func testEndBreakCountsAsTaken() {
        var schedule = BreakSchedule(at: start)
        var now = start
        run(&schedule, from: &now, seconds: 45 * 60)
        schedule.endBreak(at: now)
        XCTAssertEqual(schedule.phase, .working)
        XCTAssertEqual(schedule.activeSeconds, 0)
    }

    func testPauseHoldsBreaksUntilItEnds() {
        var schedule = BreakSchedule(at: start)
        var now = start
        run(&schedule, from: &now, seconds: 40 * 60)
        schedule.pause(until: now.addingTimeInterval(3600), at: now)
        XCTAssertTrue(schedule.isPaused(at: now))
        XCTAssertNil(schedule.secondsUntilDue(at: now, settings: settings))
        run(&schedule, from: &now, seconds: 3599)
        XCTAssertEqual(schedule.phase, .working)
        XCTAssertEqual(schedule.activeSeconds, 0)
        run(&schedule, from: &now, seconds: 1)
        XCTAssertFalse(schedule.isPaused(at: now))
        XCTAssertNil(schedule.pausedUntil)
        XCTAssertEqual(schedule.secondsUntilDue(at: now, settings: settings), 45 * 60)
        schedule.pause(until: now.addingTimeInterval(3600), at: now)
        schedule.resume(at: now)
        XCTAssertFalse(schedule.isPaused(at: now))
    }

    func testCameraOrMicrophoneInUseDefersTheBreakAndCallsAreNotIdle() {
        var schedule = BreakSchedule(at: start)
        var now = start
        run(&schedule, from: &now, seconds: 44 * 60)
        run(&schedule, from: &now, seconds: 30, inCall: true)
        XCTAssertEqual(schedule.phase, .working, "No heads-up during a call")
        run(&schedule, from: &now, seconds: 30 * 60, idle: { TimeInterval($0) }, inCall: true)
        XCTAssertEqual(schedule.phase, .waitingForCall, "A quiet call isn't time away")
        run(&schedule, from: &now, seconds: 1)
        XCTAssertEqual(schedule.phase, .headsUp, "The heads-up comes once the call ends")
        run(&schedule, from: &now, seconds: 60)
        XCTAssertEqual(schedule.phase, .onBreak)
    }

    func testCallEndingWithoutHeadsUpStartsTheBreak() {
        settings.headsUp = false
        var schedule = BreakSchedule(at: start)
        var now = start
        run(&schedule, from: &now, seconds: 45 * 60, inCall: true)
        XCTAssertEqual(schedule.phase, .waitingForCall)
        run(&schedule, from: &now, seconds: 1)
        XCTAssertEqual(schedule.phase, .onBreak)
    }

    func testACallStartingDuringABreakEndsTheOverlayAndWaits() {
        var schedule = BreakSchedule(at: start)
        var now = start
        schedule.startBreak(at: now, settings: settings)
        run(&schedule, from: &now, seconds: 1, inCall: true)
        XCTAssertEqual(schedule.phase, .waitingForCall)
        XCTAssertNil(schedule.breakEndsAt)
    }

    func testClockTimeIgnoresActivity() {
        settings.mode = .clockTime
        var schedule = BreakSchedule(at: start)
        var now = start
        run(&schedule, from: &now, seconds: 20 * 60)
        run(&schedule, from: &now, seconds: 10 * 60, idle: { TimeInterval($0) })
        XCTAssertEqual(schedule.secondsUntilDue(at: now, settings: settings), 15 * 60, "Time away before the break doesn't reset Clock Time")
        run(&schedule, from: &now, seconds: 14 * 60)
        XCTAssertEqual(schedule.phase, .headsUp)
        run(&schedule, from: &now, seconds: 60)
        XCTAssertEqual(schedule.phase, .onBreak)
    }

    func testClockTimeAwayThroughTheScheduledMomentCountsAsTaken() {
        settings.mode = .clockTime
        var schedule = BreakSchedule(at: start)
        var now = start
        run(&schedule, from: &now, seconds: 40 * 60)
        run(&schedule, from: &now, seconds: 10 * 60, idle: { TimeInterval($0) })
        XCTAssertEqual(schedule.phase, .working)
        XCTAssertEqual(schedule.secondsUntilDue(at: now, settings: settings)!, 45 * 60, accuracy: 6 * 60)
        XCTAssertGreaterThan(schedule.cycleStart, start.addingTimeInterval(44 * 60))
    }

    func testClockTimeDueWhileLockedWaitsForTheOwner() {
        settings.mode = .clockTime
        var schedule = BreakSchedule(at: start)
        var now = start
        run(&schedule, from: &now, seconds: 44 * 60)
        run(&schedule, from: &now, seconds: 120, away: true)
        XCTAssertEqual(schedule.phase, .working, "No break or heads-up on a locked screen")
        run(&schedule, from: &now, seconds: 1)
        XCTAssertEqual(schedule.phase, .onBreak, "A short absence still owes the break")
    }

    func testScreenLockAndSleepCountAsAway() {
        var schedule = BreakSchedule(at: start)
        var now = start
        run(&schedule, from: &now, seconds: 30 * 60)
        run(&schedule, from: &now, seconds: 300, away: true)
        XCTAssertEqual(schedule.activeSeconds, 0, "Locked for the break length counts as a break")
        run(&schedule, from: &now, seconds: 30 * 60)
        now += 3600
        schedule.advance(BreakInput(now: now), settings: settings)
        XCTAssertEqual(schedule.activeSeconds, 0, "An hour asleep, with no observations, counts as a break")
        XCTAssertEqual(schedule.cycleStart, now)
    }

    func testShortSleepDoesNotCountAsWork() {
        var schedule = BreakSchedule(at: start)
        var now = start
        run(&schedule, from: &now, seconds: 60)
        now += 120
        schedule.advance(BreakInput(now: now), settings: settings)
        XCTAssertEqual(schedule.activeSeconds, 60, accuracy: 0.5)
    }

    func testClockTimeSleepThroughTheBreakCountsAsTaken() {
        settings.mode = .clockTime
        var schedule = BreakSchedule(at: start)
        var now = start
        run(&schedule, from: &now, seconds: 40 * 60)
        now += 20 * 60
        schedule.advance(BreakInput(now: now), settings: settings)
        XCTAssertEqual(schedule.phase, .working)
        XCTAssertEqual(schedule.cycleStart, now)
    }

    func testTurnedOffNothingIsDueButABreakOnDemandRuns() {
        settings.enabled = false
        var schedule = BreakSchedule(at: start)
        var now = start
        run(&schedule, from: &now, seconds: 3 * 3600)
        XCTAssertEqual(schedule.phase, .working)
        XCTAssertNil(schedule.secondsUntilDue(at: now, settings: settings))
        schedule.startBreak(at: now, settings: settings)
        run(&schedule, from: &now, seconds: 299)
        XCTAssertTrue(schedule.isOnBreak)
        run(&schedule, from: &now, seconds: 1)
        XCTAssertFalse(schedule.isOnBreak)
    }

    func testRestoringNeverResumesACoveredScreen() throws {
        var schedule = BreakSchedule(at: start)
        schedule.startBreak(at: start, settings: settings)
        schedule.pausedFocusSession = true
        var restored = try JSONDecoder().decode(BreakSchedule.self, from: JSONEncoder().encode(schedule))
        XCTAssertEqual(restored, schedule)
        restored.restored(at: start.addingTimeInterval(10))
        XCTAssertEqual(restored.phase, .working)
        XCTAssertNil(restored.breakEndsAt)
        XCTAssertTrue(restored.pausedFocusSession, "The app still has to resume Focus")
    }

    func testRestartLeavesARunningBreakAlone() {
        var schedule = BreakSchedule(at: start)
        schedule.startBreak(at: start, settings: settings)
        schedule.restart(at: start.addingTimeInterval(5))
        XCTAssertTrue(schedule.isOnBreak)
    }

    func testCallStateIsOnlyNeededNearABreak() {
        var schedule = BreakSchedule(at: start)
        var now = start
        XCTAssertFalse(schedule.needsCallState(at: now, settings: settings))
        run(&schedule, from: &now, seconds: 44 * 60 - 1)
        XCTAssertTrue(schedule.needsCallState(at: now, settings: settings))
        XCTAssertFalse(schedule.needsCallState(at: now, settings: BreakPreferences()))
    }
}
