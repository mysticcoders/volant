import XCTest

@testable import VolantCore

final class BreakRecordTests: XCTestCase {
    private let start = Date(timeIntervalSince1970: 1_800_000_000)
    private let settings = BreakPreferences(enabled: true)

    /// Advances one second at a time and returns every record the schedule produced.
    private func run(_ schedule: inout BreakSchedule, from now: inout Date, seconds: Int, idle: (Int) -> TimeInterval = { _ in 0 },
                     away: Bool = false, settings: BreakPreferences? = nil) -> [BreakRecord] {
        var records: [BreakRecord] = []
        for second in 1...seconds {
            now += 1
            if let record = schedule.advance(BreakInput(now: now, idleSeconds: idle(second), away: away), settings: settings ?? self.settings) {
                records.append(record)
            }
        }
        return records
    }

    func testABreakThatRunsToItsEndIsTakenForItsFullLength() {
        var schedule = BreakSchedule(at: start)
        var now = start
        XCTAssertEqual(run(&schedule, from: &now, seconds: 45 * 60), [])
        XCTAssertTrue(schedule.isOnBreak)
        let began = now
        let records = run(&schedule, from: &now, seconds: 5 * 60)
        XCTAssertEqual(records, [BreakRecord(kind: .taken, start: began, seconds: 300, planned: 300)])
    }

    func testEndingABreakEarlyRecordsTheTimeItRan() {
        var schedule = BreakSchedule(at: start)
        schedule.startBreak(at: start, settings: settings)
        XCTAssertEqual(schedule.endBreak(at: start + 90), BreakRecord(kind: .taken, start: start, seconds: 90, planned: 300))
        XCTAssertNil(schedule.endBreak(at: start + 91))
    }

    func testSkippingBeforeOrDuringABreakIsRecordedAsSkipped() {
        var schedule = BreakSchedule(at: start)
        XCTAssertEqual(schedule.skip(at: start + 60), BreakRecord(kind: .skipped, start: start + 60, seconds: 0))
        schedule.startBreak(at: start + 100, settings: settings)
        XCTAssertEqual(schedule.skip(at: start + 120), BreakRecord(kind: .skipped, start: start + 100, seconds: 20, planned: 300))
    }

    func testPausingOrRelaunchingDuringABreakCountsTheTimeItRan() {
        var schedule = BreakSchedule(at: start)
        schedule.startBreak(at: start, settings: settings)
        XCTAssertEqual(schedule.pause(until: start + 3600, at: start + 30), BreakRecord(kind: .taken, start: start, seconds: 30, planned: 300))
        XCTAssertNil(schedule.pause(until: start + 3600, at: start + 40))
        var relaunched = BreakSchedule(at: start)
        relaunched.startBreak(at: start, settings: settings)
        XCTAssertEqual(relaunched.restored(at: start + 3600), BreakRecord(kind: .taken, start: start, seconds: 300, planned: 300))
    }

    func testTimeAwayIsOneBreakRecordedWhenTheOwnerComesBack() {
        var schedule = BreakSchedule(at: start)
        var now = start
        _ = run(&schedule, from: &now, seconds: 20 * 60)
        let left = now
        XCTAssertEqual(run(&schedule, from: &now, seconds: 12 * 60, idle: { TimeInterval($0) }), [])
        let records = run(&schedule, from: &now, seconds: 3)
        XCTAssertEqual(records.count, 1)
        XCTAssertEqual(records.first?.kind, .away)
        XCTAssertEqual(records.first?.start, left)
        XCTAssertEqual(records.first?.seconds ?? 0, 12 * 60 + 1, accuracy: 1)
        XCTAssertEqual(run(&schedule, from: &now, seconds: 60), [])
    }

    func testShortIdleAndPostponeRecordNothing() {
        var schedule = BreakSchedule(at: start)
        var now = start
        XCTAssertEqual(run(&schedule, from: &now, seconds: 200, idle: { TimeInterval($0) }), [])
        XCTAssertEqual(run(&schedule, from: &now, seconds: 10), [])
        schedule.startBreak(at: now, settings: settings)
        schedule.postpone(at: now + 10)
        XCTAssertEqual(run(&schedule, from: &now, seconds: 30), [])
    }

    func testSavedSchedulesFromBeforeHistoryStillDecode() throws {
        let saved = try JSONEncoder().encode(BreakSchedule(at: start))
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: saved) as? [String: Any])
        object.removeValue(forKey: "awayBreakSince")
        let old = try JSONSerialization.data(withJSONObject: object)
        XCTAssertNoThrow(try JSONDecoder().decode(BreakSchedule.self, from: old))
    }
}

final class BreakHistoryTests: XCTestCase {
    private var calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        return calendar
    }()

    /// Noon local time on 2026-11-17, offset by `days`, plus `seconds`.
    private func moment(days: Int = 0, seconds: TimeInterval = 0) -> Date {
        let noon = calendar.date(from: DateComponents(year: 2026, month: 11, day: 17, hour: 12))!
        return calendar.date(byAdding: .day, value: days, to: noon)!.addingTimeInterval(seconds)
    }

    func testTodayCountsTakenAndAwayAsBreaksAndSkipsSeparately() {
        let records = [
            BreakRecord(kind: .taken, start: moment(seconds: -7200), seconds: 300, planned: 300),
            BreakRecord(kind: .away, start: moment(seconds: -3600), seconds: 600),
            BreakRecord(kind: .skipped, start: moment(seconds: -60), seconds: 0),
            BreakRecord(kind: .taken, start: moment(days: -1), seconds: 120, planned: 300)
        ]
        let summary = BreakHistory.summary(records, now: moment(), calendar: calendar)
        XCTAssertEqual(summary.today, BreakHistory.Day(day: "2026-11-17", breaks: 2, skipped: 1, seconds: 900))
        XCTAssertEqual(summary.week.count, 7)
        XCTAssertEqual(summary.week.first?.day, "2026-11-11")
        XCTAssertEqual(summary.week[5], BreakHistory.Day(day: "2026-11-16", breaks: 1, seconds: 120))
        XCTAssertEqual(summary.weekBreaks, 3)
        XCTAssertEqual(summary.weekSkipped, 1)
        XCTAssertEqual(summary.averageSeconds ?? 0, 340, accuracy: 0.01)
    }

    func testLongTimeAwayAndOldRecordsAreDropped() {
        let night = BreakRecord(kind: .away, start: moment(seconds: -40_000), seconds: 30_000)
        let old = BreakRecord(kind: .taken, start: moment(days: -91), seconds: 300)
        let kept = BreakRecord(kind: .taken, start: moment(days: -89), seconds: 300)
        XCTAssertEqual(BreakHistory.pruned([night, kept, old], now: moment()), [kept])
        XCTAssertEqual(BreakHistory.summary([night], now: moment(), calendar: calendar).today.breaks, 0)
        XCTAssertNil(BreakHistory.summary([], now: moment(), calendar: calendar).averageSeconds)
    }
}

final class BreakAlertTests: XCTestCase {
    private let start = Date(timeIntervalSince1970: 1_800_000_000)
    private let settings = BreakPreferences(enabled: true, phoneAlerts: true)

    func testPhoneAlertsAreOffByDefaultAndDecode() throws {
        XCTAssertFalse(BreakPreferences().phoneAlerts)
        XCTAssertFalse(try JSONDecoder().decode(BreakPreferences.self, from: Data(#"{"phoneAlerts":"yes"}"#.utf8)).phoneAlerts)
        XCTAssertTrue(try JSONDecoder().decode(BreakPreferences.self, from: Data(#"{"phoneAlerts":true}"#.utf8)).phoneAlerts)
        XCTAssertFalse(SettingsSync.keys.contains("breaks"))
    }

    func testAlertsWhenABreakStartsAndWhenItRunsOut() {
        var schedule = BreakSchedule(at: start)
        var now = start
        var alerts: [BreakAlert] = []
        for _ in 1...(50 * 60) {
            now += 1
            let before = schedule
            let finished = schedule.advance(BreakInput(now: now), settings: settings)
            if let alert = BreakAlert.between(before, schedule, finished: finished) { alerts.append(alert) }
        }
        XCTAssertEqual(alerts, [.started, .over])
    }

    func testEndingEarlySkippingAndRelaunchSendNothing() {
        var schedule = BreakSchedule(at: start)
        schedule.startBreak(at: start, settings: settings)
        var before = schedule
        var finished = schedule.endBreak(at: start + 60)
        XCTAssertNil(BreakAlert.between(before, schedule, finished: finished))
        schedule.startBreak(at: start + 100, settings: settings)
        before = schedule
        finished = schedule.skip(at: start + 120)
        XCTAssertNil(BreakAlert.between(before, schedule, finished: finished))
        let idle = BreakSchedule(at: start)
        let relaunchRecord = BreakRecord(kind: .taken, start: start, seconds: 300, planned: 300)
        XCTAssertNil(BreakAlert.between(idle, idle, finished: relaunchRecord))
    }

    func testRecordTypesAndSubscriptionsAreDistinct() {
        XCTAssertNotEqual(BreakAlert.started.recordType, BreakAlert.over.recordType)
        XCTAssertNotEqual(BreakAlert.started.subscriptionID, BreakAlert.over.subscriptionID)
        XCTAssertEqual(BreakAlert.containerIdentifier, "iCloud.com.mysticcoders.volant")
    }
}
