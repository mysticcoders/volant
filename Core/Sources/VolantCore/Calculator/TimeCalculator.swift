import Foundation

/// Bounded, whole-query time conversion. Explicit abbreviations are fixed offsets;
/// cities and IANA identifiers follow the system timezone database.
public enum TimeCalculator {
    public struct Result: Equatable {
        public let date: Date
        public let text: String
    }

    private static let fixed: [String: Int] = [
        "utc": 0, "gmt": 0, "est": -5, "edt": -4, "pst": -8, "pdt": -7,
        "mst": -7, "mdt": -6, "cet": 1, "cest": 2, "bst": 1, "jst": 9
    ]
    private static let cities: [String: String] = [
        "paris": "Europe/Paris", "berlin": "Europe/Berlin", "london": "Europe/London",
        "ldn": "Europe/London", "new york": "America/New_York", "nyc": "America/New_York",
        "los angeles": "America/Los_Angeles", "la": "America/Los_Angeles",
        "san francisco": "America/Los_Angeles", "sf": "America/Los_Angeles",
        "tokyo": "Asia/Tokyo", "dubai": "Asia/Dubai", "singapore": "Asia/Singapore",
        "sydney": "Australia/Sydney", "chicago": "America/Chicago", "toronto": "America/Toronto",
        "kolkata": "Asia/Kolkata", "mumbai": "Asia/Kolkata", "hong kong": "Asia/Hong_Kong"
    ]
    private static let identifiers = Dictionary(uniqueKeysWithValues:
        TimeZone.knownTimeZoneIdentifiers.map { ($0.lowercased(), $0) })
    private static let expression = try! NSRegularExpression(pattern:
        #"^(?:(\d{4}-\d{2}-\d{2})\s+)?(\d{1,2})(?::(\d{2}))?\s*(am|pm)?\s+(.+)$"#)

    public static func evaluate(_ text: String, now: Date = Date(), localZone: TimeZone = .current) -> Result? {
        guard text.utf8.count <= 256 else { return nil }
        let query = text.lowercased().split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
        if query.hasPrefix("time in ") || query.hasPrefix("now in ") {
            let name = String(query.dropFirst(query.hasPrefix("time") ? 8 : 7))
            guard let zone = resolve(name, local: localZone) else { return nil }
            return result(now, zone: zone)
        }
        guard let match = expression.firstMatch(in: query, range: NSRange(query.startIndex..., in: query)) else { return nil }
        func part(_ index: Int) -> String? {
            guard let range = Range(match.range(at: index), in: query) else { return nil }
            return String(query[range])
        }
        guard var hour = part(2).flatMap(Int.init), let rest = part(5) else { return nil }
        let minute = part(3).flatMap(Int.init) ?? 0
        guard minute < 60 else { return nil }
        if let meridiem = part(4) {
            guard (1...12).contains(hour) else { return nil }
            hour = hour % 12 + (meridiem == "pm" ? 12 : 0)
        } else {
            guard hour < 24, part(3) != nil else { return nil }
        }
        let pieces = rest.components(separatedBy: " in ")
        let targets = pieces.count == 1 ? rest.components(separatedBy: " to ") : pieces
        guard targets.count <= 2,
              let source = resolve(targets[0].hasPrefix("in ") ? String(targets[0].dropFirst(3)) : targets[0], local: localZone),
              let destination = targets.count == 2 ? resolve(targets[1], local: localZone) : localZone else { return nil }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = source
        var day = calendar.dateComponents([.year, .month, .day], from: now)
        if let explicit = part(1) {
            let fields = explicit.split(separator: "-").compactMap { Int($0) }
            day = DateComponents(year: fields[0], month: fields[1], day: fields[2])
        }
        guard let start = calendar.date(from: day),
              calendar.dateComponents([.year, .month, .day], from: start) == day else { return nil }
        var clock = day
        clock.hour = hour
        clock.minute = minute
        clock.second = 0
        let anchor = start.addingTimeInterval(-1)
        guard let first = calendar.nextDate(after: anchor, matching: clock, matchingPolicy: .strict, repeatedTimePolicy: .first),
              let last = calendar.nextDate(after: anchor, matching: clock, matchingPolicy: .strict, repeatedTimePolicy: .last),
              first == last else { return nil } // Never guess DST gaps or repeated wall times.
        return result(first, zone: destination)
    }

    private static func resolve(_ name: String, local: TimeZone) -> TimeZone? {
        if ["local", "here", "my time"].contains(name) { return local }
        if let hours = fixed[name] { return TimeZone(secondsFromGMT: hours * 3600) }
        if let identifier = cities[name] ?? identifiers[name] { return TimeZone(identifier: identifier) }
        return nil // CST/IST and broad geographic names are intentionally ambiguous.
    }

    private static func result(_ date: Date, zone: TimeZone) -> Result {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        let parts = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        let offset = zone.secondsFromGMT(for: date)
        let label = zone.abbreviation(for: date) ?? zone.identifier
        let utc = String(format: "UTC%@%02d:%02d", offset < 0 ? "−" : "+", abs(offset) / 3600, abs(offset) % 3600 / 60)
        let day = String(format: "%04d-%02d-%02d", parts.year!, parts.month!, parts.day!)
        let clock = String(format: "%02d:%02d", parts.hour!, parts.minute!)
        // Always include the date, so inferred dates and midnight rollover are visible and copyable.
        return Result(date: date, text: "\(clock) \(label) (\(utc)) · \(day)")
    }
}
