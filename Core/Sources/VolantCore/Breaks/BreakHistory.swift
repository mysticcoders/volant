import Foundation

/// One break as it happened: taken (started and run, to its end or ended early), skipped, or time
/// away from the Mac long enough to count as a break. It holds only the kind, when it began and how
/// long it lasted, never what the owner was doing.
public struct BreakRecord: Codable, Equatable, Sendable {
    public enum Kind: String, Codable, Sendable {
        case taken, skipped, away
    }

    public var kind: Kind
    public var start: Date
    /// How long the break lasted; for a skip, the time spent on a running break before it.
    public var seconds: TimeInterval
    /// The break's planned length; zero for time away and for a skip before a break began.
    public var planned: TimeInterval

    public init(kind: Kind, start: Date, seconds: TimeInterval, planned: TimeInterval = 0) {
        self.kind = kind
        self.start = start
        self.seconds = seconds
        self.planned = planned
    }
}

/// The owner's breaks on this Mac, summarized per local day for Settings › Your Volant. Records are
/// kept for `keptDays`, never synced or sent anywhere.
public enum BreakHistory {
    /// Records older than this many days are dropped.
    public static let keptDays = 90
    /// Time away longer than this, such as a night or a weekend, isn't a break and isn't kept.
    public static let longestAway: TimeInterval = 3600

    /// One local day's breaks.
    public struct Day: Equatable, Sendable {
        public let day: String
        /// Breaks taken, including time away that counted as one.
        public let breaks: Int
        public let skipped: Int
        /// Time spent on those breaks.
        public let seconds: TimeInterval

        public init(day: String, breaks: Int = 0, skipped: Int = 0, seconds: TimeInterval = 0) {
            self.day = day
            self.breaks = breaks
            self.skipped = skipped
            self.seconds = seconds
        }
    }

    /// Today and the last week, oldest day first, ending today.
    public struct Summary: Equatable, Sendable {
        public let today: Day
        public let week: [Day]
        public var weekBreaks: Int { week.reduce(0) { $0 + $1.breaks } }
        public var weekSkipped: Int { week.reduce(0) { $0 + $1.skipped } }
        public var weekSeconds: TimeInterval { week.reduce(0) { $0 + $1.seconds } }
        /// The average break over the week, or nil without one.
        public var averageSeconds: TimeInterval? { weekBreaks > 0 ? weekSeconds / TimeInterval(weekBreaks) : nil }
    }

    /// Whether a record is worth keeping: time away up to `longestAway`, and anything else.
    public static func keeps(_ record: BreakRecord) -> Bool {
        record.kind != .away || (record.seconds > 0 && record.seconds <= longestAway)
    }

    /// The records still inside `keptDays` of `now`, oldest first.
    public static func pruned(_ records: [BreakRecord], now: Date) -> [BreakRecord] {
        let cutoff = now.addingTimeInterval(-TimeInterval(keptDays) * 86_400)
        return records.filter { $0.start >= cutoff && keeps($0) }.sorted { $0.start < $1.start }
    }

    /// Counts each day of the last week, by the local day each break began.
    public static func summary(_ records: [BreakRecord], now: Date, calendar: Calendar = .current) -> Summary {
        let today = calendar.startOfDay(for: now)
        let keys = (0..<7).reversed().compactMap { calendar.date(byAdding: .day, value: -$0, to: today) }.map { UsageStats.dayKey($0, calendar: calendar) }
        var breaks: [String: Int] = [:], skipped: [String: Int] = [:], seconds: [String: TimeInterval] = [:]
        for record in records where keeps(record) {
            let key = UsageStats.dayKey(record.start, calendar: calendar)
            switch record.kind {
            case .taken, .away:
                breaks[key, default: 0] += 1
                seconds[key, default: 0] += record.seconds
            case .skipped:
                skipped[key, default: 0] += 1
            }
        }
        let week = keys.map { Day(day: $0, breaks: breaks[$0] ?? 0, skipped: skipped[$0] ?? 0, seconds: seconds[$0] ?? 0) }
        return Summary(today: week.last ?? Day(day: UsageStats.dayKey(now, calendar: calendar)), week: week)
    }
}
