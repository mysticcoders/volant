import Foundation

/// The owner's own usage, summarized for Settings › Your Volant from what `UsageStore` keeps on this Mac.
/// Nothing here leaves the Mac: the inputs are the per-day use counts and the ranking rows, and the
/// output is only shown in Settings.
public enum UsageStats {
    /// One local calendar day and how many launcher choices were counted on it.
    public struct Day: Equatable, Sendable {
        public let day: String
        public let uses: Int
        public init(day: String, uses: Int) { self.day = day; self.uses = uses }
    }

    /// The activity numbers for a window of days ending today.
    public struct Summary: Equatable, Sendable {
        /// Every day of the window, oldest first, with zero for days without uses.
        public let days: [Day]
        public let total: Int
        public let activeDays: Int
        public let busiest: Day?
        /// Consecutive days with at least one use, ending today, or yesterday when today has none yet.
        public let streak: Int
        /// The earliest day counted at all, inside or outside the window.
        public let since: String?
    }

    /// A ranking row: its key, stored frecency score and last use.
    public struct Ranked: Equatable, Sendable {
        public let key: String
        public let score: Double
        public let last: Date
        public init(key: String, score: Double, last: Date) { self.key = key; self.score = score; self.last = last }
    }

    /// The kinds of choice Settings lists. Files, contacts, clips, notes and snippets are left out on
    /// purpose: their keys carry paths or content that a stats page has no reason to show.
    public enum Kind: CaseIterable, Sendable {
        case apps, commands, extensions

        /// Whether a ranking key belongs to this kind.
        public func contains(_ key: String) -> Bool {
            switch self {
            case .apps: return key.hasPrefix("app:")
            case .commands: return ["core:", "system-action:", "command:"].contains { key.hasPrefix($0) }
            case .extensions: return key.hasPrefix("ext:")
            }
        }

        /// The key the kind groups by. An extension's runs differ by their input, so they are merged
        /// into one entry per extension (`ext:<id>`); other keys are already one per item.
        public func group(_ key: String) -> String {
            guard self == .extensions else { return key }
            let rest = key.dropFirst("ext:".count)
            return "ext:" + (rest.split(separator: ":", maxSplits: 1).first.map(String.init) ?? String(rest))
        }
    }

    /// The local day key, `yyyy-MM-dd`, for a moment in the given calendar.
    public static func dayKey(_ date: Date, calendar: Calendar = .current) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }

    /// Summarizes per-day counts over the `window` days ending on `now`'s day.
    public static func summary(daily: [String: Int], now: Date = Date(), calendar: Calendar = .current, window: Int = 30) -> Summary {
        let today = calendar.startOfDay(for: now)
        let days: [Day] = (0..<max(window, 1)).reversed().compactMap { offset in
            calendar.date(byAdding: .day, value: -offset, to: today).map { date in
                let key = dayKey(date, calendar: calendar)
                return Day(day: key, uses: max(0, daily[key] ?? 0))
            }
        }
        let busiest = days.filter { $0.uses > 0 }.max { $0.uses < $1.uses || ($0.uses == $1.uses && $0.day < $1.day) }
        return Summary(days: days, total: days.reduce(0) { $0 + $1.uses }, activeDays: days.filter { $0.uses > 0 }.count,
                       busiest: busiest, streak: streak(daily: daily, today: today, calendar: calendar),
                       since: daily.filter { $0.value > 0 }.keys.min())
    }

    /// The top `limit` entries of one kind by current frecency, merged by group and highest first.
    /// Entries whose score has decayed below a twentieth of one use are dropped, as in the launcher.
    public static func top(_ kind: Kind, records: [Ranked], now: Date = Date(), limit: Int = 5) -> [Ranked] {
        var merged: [String: Ranked] = [:]
        for record in records where kind.contains(record.key) {
            let key = kind.group(record.key)
            let score = Frecency.decayed(score: record.score, last: record.last, now: now)
            let previous = merged[key]
            merged[key] = Ranked(key: key, score: (previous?.score ?? 0) + score, last: max(previous?.last ?? record.last, record.last))
        }
        return merged.values.filter { $0.score > 0.05 }
            .sorted { $0.score != $1.score ? $0.score > $1.score : $0.key < $1.key }
            .prefix(limit).map { $0 }
    }

    /// Counts back from today, or from yesterday when today has no uses yet, so a streak is not shown
    /// as broken first thing in the morning.
    private static func streak(daily: [String: Int], today: Date, calendar: Calendar) -> Int {
        var day = today
        if (daily[dayKey(day, calendar: calendar)] ?? 0) <= 0 {
            guard let yesterday = calendar.date(byAdding: .day, value: -1, to: day) else { return 0 }
            day = yesterday
        }
        var count = 0
        while (daily[dayKey(day, calendar: calendar)] ?? 0) > 0 {
            count += 1
            guard let previous = calendar.date(byAdding: .day, value: -1, to: day) else { break }
            day = previous
        }
        return count
    }
}
