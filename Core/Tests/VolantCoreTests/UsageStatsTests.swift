import XCTest

@testable import VolantCore

/// Settings › Your Volant: day windows, streaks and per-kind rankings from fictional local usage.
final class UsageStatsTests: XCTestCase {
    private var calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        return calendar
    }()

    /// Noon on a fixed fictional day, so day keys never depend on when the test runs.
    private var now: Date { calendar.date(from: DateComponents(year: 2026, month: 3, day: 15, hour: 12))! }

    func testDayKeyUsesTheLocalCalendarDay() {
        let lateEvening = calendar.date(from: DateComponents(year: 2026, month: 3, day: 15, hour: 23, minute: 30))!
        XCTAssertEqual(UsageStats.dayKey(lateEvening, calendar: calendar), "2026-03-15")
    }

    func testSummaryFillsTheWindowAndFindsTheBusiestDay() {
        let daily = ["2026-03-15": 4, "2026-03-14": 9, "2026-03-10": 9, "2026-02-01": 50]
        let summary = UsageStats.summary(daily: daily, now: now, calendar: calendar, window: 7)
        XCTAssertEqual(summary.days.map(\.day), ["2026-03-09", "2026-03-10", "2026-03-11", "2026-03-12", "2026-03-13", "2026-03-14", "2026-03-15"])
        XCTAssertEqual(summary.total, 22)
        XCTAssertEqual(summary.activeDays, 3)
        XCTAssertEqual(summary.busiest, UsageStats.Day(day: "2026-03-14", uses: 9))
        XCTAssertEqual(summary.since, "2026-02-01")
    }

    func testEmptyHistoryHasNoBusiestDayOrStreak() {
        let summary = UsageStats.summary(daily: [:], now: now, calendar: calendar)
        XCTAssertEqual(summary.days.count, 30)
        XCTAssertEqual(summary.total, 0)
        XCTAssertNil(summary.busiest)
        XCTAssertNil(summary.since)
        XCTAssertEqual(summary.streak, 0)
    }

    func testStreakCountsBackFromTodayOrYesterday() {
        XCTAssertEqual(UsageStats.summary(daily: ["2026-03-15": 1, "2026-03-14": 2, "2026-03-13": 1, "2026-03-11": 5], now: now, calendar: calendar).streak, 3)
        XCTAssertEqual(UsageStats.summary(daily: ["2026-03-14": 2, "2026-03-13": 1], now: now, calendar: calendar).streak, 2)
        XCTAssertEqual(UsageStats.summary(daily: ["2026-03-13": 1], now: now, calendar: calendar).streak, 0)
    }

    func testTopKeepsOnlyItsKindAndLeavesPrivateKindsOut() {
        let records = [
            UsageStats.Ranked(key: "app:/Applications/Fictional.app", score: 3, last: now),
            UsageStats.Ranked(key: "core:notes", score: 5, last: now),
            UsageStats.Ranked(key: "system-action:lockScreen", score: 2, last: now),
            UsageStats.Ranked(key: "file:/Users/someone/secret.txt", score: 99, last: now),
            UsageStats.Ranked(key: "clip:42", score: 99, last: now)
        ]
        XCTAssertEqual(UsageStats.top(.apps, records: records, now: now).map(\.key), ["app:/Applications/Fictional.app"])
        XCTAssertEqual(UsageStats.top(.commands, records: records, now: now).map(\.key), ["core:notes", "system-action:lockScreen"])
        XCTAssertTrue(UsageStats.top(.extensions, records: records, now: now).isEmpty)
    }

    func testExtensionRunsMergeByExtension() {
        let earlier = now.addingTimeInterval(-3600)
        let records = [
            UsageStats.Ranked(key: "ext:com.example.weather:paris", score: 1, last: earlier),
            UsageStats.Ranked(key: "ext:com.example.weather:tokyo", score: 2, last: now),
            UsageStats.Ranked(key: "ext:com.example.hello:", score: 2.5, last: now)
        ]
        let top = UsageStats.top(.extensions, records: records, now: now)
        XCTAssertEqual(top.map(\.key), ["ext:com.example.weather", "ext:com.example.hello"])
        XCTAssertEqual(top.first?.last, now)
    }

    func testTopDropsDecayedEntriesAndHonorsTheLimit() {
        let longAgo = now.addingTimeInterval(-Frecency.halfLife * 10)
        let records = (1...8).map { UsageStats.Ranked(key: "core:c\($0)", score: Double($0), last: now) }
            + [UsageStats.Ranked(key: "core:forgotten", score: 1, last: longAgo)]
        let top = UsageStats.top(.commands, records: records, now: now, limit: 3)
        XCTAssertEqual(top.map(\.key), ["core:c8", "core:c7", "core:c6"])
        XCTAssertFalse(UsageStats.top(.commands, records: records, now: now, limit: 20).contains { $0.key == "core:forgotten" })
    }
}
