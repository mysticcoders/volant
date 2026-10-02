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

    public static func evaluate(_ text: String, now: Date = Date(), localZone: TimeZone = .current, locale: Locale = .current) -> Result? {
        guard text.utf8.count <= 256 else { return nil }
        let query = text.lowercased().split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
        var localCalendar = Calendar(identifier: .gregorian)
        localCalendar.timeZone = localZone
        let baseline = localCalendar.dateComponents([.year, .month, .day], from: now)
        if query.hasPrefix("time in ") || query.hasPrefix("now in ") {
            let name = String(query.dropFirst(query.hasPrefix("time") ? 8 : 7))
            guard let zone = resolve(name, local: localZone) else { return nil }
            return result(now, zone: zone, label: destinationLabel(name, zone: zone), baseline: baseline, explicitDate: false, locale: locale)
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
        let name = targets.count == 2 ? targets[1] : "local"
        return result(first, zone: destination, label: destinationLabel(name, zone: destination), baseline: baseline, explicitDate: part(1) != nil, locale: locale)
    }

    private static func resolve(_ name: String, local: TimeZone) -> TimeZone? {
        if ["local", "here", "my time"].contains(name) { return local }
        if let hours = fixed[name] { return TimeZone(secondsFromGMT: hours * 3600) }
        if let identifier = cities[name] ?? identifiers[name] { return TimeZone(identifier: identifier) }
        return nil // CST/IST and broad geographic names are intentionally ambiguous.
    }

    private static func destinationLabel(_ name: String, zone: TimeZone) -> String {
        if ["local", "here", "my time"].contains(name) { return "· your time" }
        if fixed[name] != nil { return name.uppercased() }
        let city = zone.identifier.split(separator: "/").last.map(String.init)?.replacingOccurrences(of: "_", with: " ")
        return city.map { "in \($0)" } ?? zone.identifier
    }

    private static func result(_ date: Date, zone: TimeZone, label: String,
                               baseline: DateComponents, explicitDate: Bool, locale: Locale) -> Result {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        let parts = calendar.dateComponents([.hour, .minute], from: date)
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = zone
        formatter.locale = locale
        formatter.dateFormat = "h:mm a"
        let clock: String
        if parts.hour == 0 && parts.minute == 0 { clock = "Midnight" }
        else if parts.hour == 12 && parts.minute == 0 { clock = "Noon" }
        else { clock = formatter.string(from: date) }
        var suffix = ""
        if explicitDate {
            formatter.setLocalizedDateFormatFromTemplate("MMM d yyyy")
            suffix = " · " + formatter.string(from: date)
        } else if let base = calendar.date(from: baseline),
                  let days = calendar.dateComponents([.day], from: base, to: calendar.startOfDay(for: date)).day {
            if days == 1 { suffix = " · tomorrow" }
            else if days == -1 { suffix = " · yesterday" }
            else if days != 0 {
                formatter.setLocalizedDateFormatFromTemplate("MMM d yyyy")
                suffix = " · " + formatter.string(from: date)
            }
        }
        return Result(date: date, text: "\(clock) \(label)\(suffix)")
    }
}
