import Foundation

/// National public holidays computed by rule, so workday counts can skip them: US federal
/// holidays, UK (England and Wales) bank holidays, and the national holidays of Germany, France and
/// Canada (federal). Weekend substitution follows each country: the US moves Saturday holidays to
/// Friday and Sunday ones to Monday; the UK and Canada move them to the next free weekday; Germany
/// and France do not move them. One-off holidays proclaimed for a single year are not included.
enum PublicHolidays {
    /// Adjectives for the card, keyed by region code.
    static let names = ["US": "US", "GB": "UK", "DE": "German", "FR": "French", "CA": "Canadian"]

    private static let lock = NSLock()
    private static var cache: [String: Set<Int>] = [:]

    static func supports(_ region: String?) -> Bool {
        region.map { names[$0] != nil } ?? false
    }

    /// Whether the given Gregorian date is a public holiday in `region`.
    static func isHoliday(year: Int, month: Int, day: Int, region: String?) -> Bool {
        guard let region, supports(region) else { return false }
        return holidays(region, year).contains(key(year, month, day))
    }

    /// Every holiday date in `year`, including substitutes that move in from a neighboring year,
    /// such as a US New Year's Day observed on December 31.
    static func holidays(_ region: String, _ year: Int) -> Set<Int> {
        let cacheKey = "\(region)-\(year)"
        lock.lock()
        defer { lock.unlock() }
        if let cached = cache[cacheKey] { return cached }
        var all = Set<Int>()
        for candidate in (year - 1)...(year + 1) { all.formUnion(rules(region, candidate)) }
        let inYear = all.filter { $0 / 10_000 == year }
        cache[cacheKey] = inYear
        return inYear
    }

    private static func rules(_ region: String, _ y: Int) -> Set<Int> {
        let easter = DateCalculator.easter(y)
        let e = key(y, easter.month, easter.day)
        switch region {
        case "US":
            let observed = [(1, 1), (6, 19), (7, 4), (11, 11), (12, 25)].map { usObserved(key(y, $0.0, $0.1)) }
            return Set(observed + [nth(y, 1, 2, 3), nth(y, 2, 2, 3), last(y, 5, 2), nth(y, 9, 2, 1), nth(y, 10, 2, 2), nth(y, 11, 5, 4)])
        case "GB":
            var taken: Set<Int> = [shift(e, -2), shift(e, 1), nth(y, 5, 2, 1), last(y, 5, 2), last(y, 8, 2)]
            for day in [key(y, 1, 1), key(y, 12, 25), key(y, 12, 26)] { taken.insert(substitute(day, avoiding: taken)) }
            return taken
        case "DE":
            return [key(y, 1, 1), shift(e, -2), shift(e, 1), key(y, 5, 1), shift(e, 39), shift(e, 50), key(y, 10, 3), key(y, 12, 25), key(y, 12, 26)]
        case "FR":
            return [key(y, 1, 1), shift(e, 1), key(y, 5, 1), key(y, 5, 8), shift(e, 39), shift(e, 50), key(y, 7, 14), key(y, 8, 15),
                    key(y, 11, 1), key(y, 11, 11), key(y, 12, 25)]
        case "CA":
            let victoria = key(y, 5, 24 - (weekdayOf(key(y, 5, 24)) - 2 + 7) % 7)
            var taken: Set<Int> = [shift(e, -2), victoria, nth(y, 9, 2, 1), nth(y, 10, 2, 2)]
            for day in [key(y, 1, 1), key(y, 7, 1), key(y, 9, 30), key(y, 11, 11), key(y, 12, 25), key(y, 12, 26)] {
                taken.insert(substitute(day, avoiding: taken))
            }
            return taken
        default:
            return []
        }
    }

    /// A date as yyyymmdd, which sorts and compares like the date.
    static func key(_ year: Int, _ month: Int, _ day: Int) -> Int { year * 10_000 + month * 100 + day }

    private static let utc: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()

    private static func date(_ key: Int) -> Date {
        utc.date(from: DateComponents(year: key / 10_000, month: key / 100 % 100, day: key % 100))!
    }

    private static func shift(_ key: Int, _ days: Int) -> Int {
        let parts = utc.dateComponents([.year, .month, .day], from: utc.date(byAdding: .day, value: days, to: date(key))!)
        return Self.key(parts.year!, parts.month!, parts.day!)
    }

    /// Sunday is 1, Saturday 7.
    private static func weekdayOf(_ key: Int) -> Int {
        DateCalculator.weekday(year: key / 10_000, month: key / 100 % 100, day: key % 100)
    }

    /// The `n`th given weekday of a month.
    private static func nth(_ y: Int, _ month: Int, _ weekday: Int, _ n: Int) -> Int {
        let first = weekdayOf(key(y, month, 1))
        return key(y, month, 1 + (weekday - first + 7) % 7 + 7 * (n - 1))
    }

    /// The last given weekday of a month.
    private static func last(_ y: Int, _ month: Int, _ weekday: Int) -> Int {
        let lastDay = utc.range(of: .day, in: .month, for: date(key(y, month, 1)))!.count
        let end = weekdayOf(key(y, month, lastDay))
        return key(y, month, lastDay - (end - weekday + 7) % 7)
    }

    private static func usObserved(_ key: Int) -> Int {
        switch weekdayOf(key) {
        case 7: return shift(key, -1)
        case 1: return shift(key, 1)
        default: return key
        }
    }

    /// The holiday itself on a weekday, otherwise the next weekday not already a holiday.
    private static func substitute(_ key: Int, avoiding taken: Set<Int>) -> Int {
        var day = key
        while [1, 7].contains(weekdayOf(day)) || taken.contains(day) {
            day = shift(day, 1)
        }
        return day
    }
}
