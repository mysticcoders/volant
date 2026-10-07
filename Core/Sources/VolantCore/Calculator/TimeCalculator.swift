import Foundation

/// Bounded, whole-query time conversion. UTC and GMT are fixed offsets. Regional abbreviations
/// name that region's clock as people use them, so "4pm CET" in July means Central European wall
/// time; they, cities and IANA identifiers follow the system timezone database. One day word
/// (today, tonight, tomorrow, yesterday or a weekday) may appear anywhere, counted from the owner's
/// local day; with a day word, a time needs no zone, as in "7:30pm tomorrow". "noon" and "midnight"
/// read as 12pm and 12am, so "noon in tokyo" and "midnight PST in London" work. "time diff Paris"
/// reports how far a place's clock is from the owner's. Names the built-in
/// lists do not know fall back to `CityDirectory`, then IATA codes in `AirportDirectory`.
public enum TimeCalculator {
    public struct Result: Equatable {
        public let date: Date
        /// The single-line answer Copy uses, such as "Midnight CET · tomorrow".
        public let text: String
        /// The clock and zone without day context, such as "Midnight CET" or "4:00 PM" for local time.
        public let headline: String
        /// Day context for the answer, such as "Tomorrow" or "Your time · Today".
        public let detail: String
        /// When the query's time falls in its own zone, such as "Friday, October 2", or "Now".
        public let source: String
        /// The same conversion the other way, for Shift-Command-Return: "7:00pm cet in est".
        public var swap: String? = nil
    }

    private static let fixed: [String: Int] = ["utc": 0, "gmt": 0]
    /// Either spelling selects the region; the label shows whichever is in effect on that date.
    private static let regions: [String: (zone: String, standard: String, daylight: String)] = {
        let eastern = ("America/New_York", "EST", "EDT"), mountain = ("America/Denver", "MST", "MDT")
        let pacific = ("America/Los_Angeles", "PST", "PDT"), central = ("Europe/Berlin", "CET", "CEST")
        return ["est": eastern, "edt": eastern, "mst": mountain, "mdt": mountain, "pst": pacific, "pdt": pacific,
                "cet": central, "cest": central, "bst": ("Europe/London", "GMT", "BST"), "jst": ("Asia/Tokyo", "JST", "JST")]
    }()
    /// Common names and nicknames, with the city each one labels: "sf" answers "in San Francisco"
    /// on Los Angeles time.
    private static let cities: [String: (zone: String, name: String)] = {
        let losAngeles = ("America/Los_Angeles", "Los Angeles"), sanFrancisco = ("America/Los_Angeles", "San Francisco")
        let newYork = ("America/New_York", "New York"), london = ("Europe/London", "London")
        return ["paris": ("Europe/Paris", "Paris"), "berlin": ("Europe/Berlin", "Berlin"), "london": london, "ldn": london,
                "new york": newYork, "nyc": newYork, "los angeles": losAngeles, "la": losAngeles,
                "san francisco": sanFrancisco, "sf": sanFrancisco, "tokyo": ("Asia/Tokyo", "Tokyo"),
                "dubai": ("Asia/Dubai", "Dubai"), "singapore": ("Asia/Singapore", "Singapore"),
                "sydney": ("Australia/Sydney", "Sydney"), "chicago": ("America/Chicago", "Chicago"),
                "toronto": ("America/Toronto", "Toronto"), "kolkata": ("Asia/Kolkata", "Kolkata"),
                "mumbai": ("Asia/Kolkata", "Mumbai"), "hong kong": ("Asia/Hong_Kong", "Hong Kong")]
    }()
    private static let identifiers = Dictionary(uniqueKeysWithValues:
        TimeZone.knownTimeZoneIdentifiers.map { ($0.lowercased(), $0) })
    /// The city part of every IANA identifier, so "lisbon" finds Europe/Lisbon. Where two
    /// identifiers share a city, the first in the system's sorted list wins.
    private static let zoneCities: [String: String] = {
        var names: [String: String] = [:]
        for identifier in TimeZone.knownTimeZoneIdentifiers where identifier.contains("/") {
            guard let city = identifier.split(separator: "/").last else { continue }
            let name = city.replacingOccurrences(of: "_", with: " ").lowercased()
            if names[name] == nil { names[name] = identifier }
        }
        return names
    }()
    private static let weekdays: [String: Int] = [
        "sunday": 1, "sun": 1, "monday": 2, "mon": 2, "tuesday": 3, "tue": 3, "tues": 3, "wednesday": 4, "wed": 4,
        "thursday": 5, "thu": 5, "thurs": 5, "friday": 6, "fri": 6, "saturday": 7, "sat": 7
    ]
    private static let expression = try! NSRegularExpression(pattern:
        #"^(?:(\d{4}-\d{2}-\d{2})\s+)?(\d{1,2})(?::(\d{2}))?\s*(am|pm)?(?:\s+(.+))?$"#)

    public static func evaluate(_ text: String, now: Date = Date(), localZone: TimeZone = .current, locale: Locale = .current) -> Result? {
        guard text.utf8.count <= 256 else { return nil }
        var localCalendar = Calendar(identifier: .gregorian)
        localCalendar.timeZone = localZone
        let baseline = localCalendar.dateComponents([.year, .month, .day], from: now)
        var words = text.lowercased().split(whereSeparator: { $0.isWhitespace }).map { ["noon": "12pm", "midnight": "12am"][$0] ?? String($0) }
        for index in words.indices.reversed() where index + 2 < words.count
            && weekdays[words[index]] != nil && words[index + 1] == "after" && words[index + 2] == "next" {
            words.removeSubrange((index + 1)...(index + 2))
            words[index] = "afternext " + words[index]
        }
        for index in words.indices.reversed() where index + 1 < words.count
            && ["next", "this", "last"].contains(words[index]) && weekdays[words[index + 1]] != nil {
            words[index] += " " + words.remove(at: index + 1)
        }
        let dayWords = words.indices.filter { dayOffset(words[$0], now: now, calendar: localCalendar) != nil }
        guard dayWords.count <= 1 else { return nil }
        var relativeDay: Int?
        if let index = dayWords.first {
            relativeDay = dayOffset(words[index], now: now, calendar: localCalendar)
            words.remove(at: index)
            if index < words.count, words[index] == "at" { words.remove(at: index) }
            else if index > 0, words[index - 1] == "at" { words.remove(at: index - 1) }
        }
        let query = words.joined(separator: " ")
        if let name = differenceTarget(query) {
            guard relativeDay == nil, let zone = resolve(name, local: localZone) else { return nil }
            return difference(zone, label: destinationLabel(name, zone: zone, date: now), local: localZone, now: now, locale: locale)
        }
        if query.hasPrefix("time in ") || query.hasPrefix("now in ") {
            guard relativeDay == nil else { return nil }
            let name = String(query.dropFirst(query.hasPrefix("time") ? 8 : 7))
            if let later = elapsed(name) ?? elapsed(name + " in local"), let zone = resolve(later.place, local: localZone) {
                let date = now.addingTimeInterval(later.seconds)
                return result(date, zone: zone, label: destinationLabel(later.place, zone: zone, date: date), baseline: baseline,
                              explicitDate: false, source: later.phrase, now: now, locale: locale)
            }
            guard let zone = resolve(name, local: localZone) else { return nil }
            return result(now, zone: zone, label: destinationLabel(name, zone: zone, date: now), baseline: baseline, explicitDate: false,
                          source: "Now", now: now, locale: locale)
        }
        guard let match = expression.firstMatch(in: query, range: NSRange(query.startIndex..., in: query)) else { return nil }
        func part(_ index: Int) -> String? {
            guard let range = Range(match.range(at: index), in: query) else { return nil }
            return String(query[range])
        }
        guard var hour = part(2).flatMap(Int.init), part(5) != nil || relativeDay != nil,
              part(1) == nil || relativeDay == nil else { return nil }
        let minute = part(3).flatMap(Int.init) ?? 0
        guard minute < 60 else { return nil }
        if let meridiem = part(4) {
            guard (1...12).contains(hour) else { return nil }
            hour = hour % 12 + (meridiem == "pm" ? 12 : 0)
        } else {
            guard hour < 24, part(3) != nil else { return nil }
        }
        let rest = part(5) ?? "local"
        let pieces = rest.components(separatedBy: " in ")
        let targets = pieces.count == 1 ? rest.components(separatedBy: " to ") : pieces
        guard targets.count <= 2,
              let source = resolve(targets[0].hasPrefix("in ") ? String(targets[0].dropFirst(3)) : targets[0], local: localZone),
              let destination = targets.count == 2 ? resolve(targets[1], local: localZone) : localZone else { return nil }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = source
        var day = calendar.dateComponents([.year, .month, .day], from: now)
        if let relativeDay {
            guard let target = localCalendar.date(byAdding: .day, value: relativeDay, to: localCalendar.startOfDay(for: now)) else { return nil }
            day = localCalendar.dateComponents([.year, .month, .day], from: target)
        } else if let explicit = part(1) {
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
        if part(5) == nil, let relativeDay {
            return localResult(first, offset: relativeDay, zone: localZone, now: now, locale: locale)
        }
        let name = targets.count == 2 ? targets[1] : "local"
        var answer = result(first, zone: destination, label: destinationLabel(name, zone: destination, date: first), baseline: baseline,
                            explicitDate: part(1) != nil, source: describe(first, in: source, now: now, locale: locale), now: now, locale: locale)
        let sourceName = targets[0].hasPrefix("in ") ? String(targets[0].dropFirst(3)) : targets[0]
        answer.swap = swapQuery(first, from: destination, name: name, to: sourceName, now: now)
        return answer
    }

    /// The conversion reversed: the answer's wall time in its zone, converted back. The date is
    /// written out when the answer falls on another day there, so the reverse stays exact.
    private static func swapQuery(_ date: Date, from zone: TimeZone, name: String, to source: String, now: Date) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = zone
        formatter.dateFormat = calendar.isDate(date, inSameDayAs: now) ? "h:mma" : "yyyy-MM-dd h:mma"
        return "\(formatter.string(from: date).lowercased()) \(name) in \(source)"
    }

    private static let elapsedPattern = try! NSRegularExpression(pattern:
        #"^(\d+(?:\.\d+)?)\s*(minutes?|mins?|hours?|hrs?|h|days?)\s+in\s+(.+)$"#)

    /// "4 hours in san francisco" after "time in": elapsed minutes, hours or days, then a place.
    /// "time in 4 hours" passes its place as "local".
    private static func elapsed(_ text: String) -> (seconds: Double, place: String, phrase: String)? {
        guard let found = elapsedPattern.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let numberRange = Range(found.range(at: 1), in: text), let unitRange = Range(found.range(at: 2), in: text),
              let placeRange = Range(found.range(at: 3), in: text), let value = Double(text[numberRange]) else { return nil }
        let unit = String(text[unitRange])
        let (size, name): (Double, String) = unit.hasPrefix("d") ? (86_400, "day") : unit.hasPrefix("m") ? (60, "minute") : (3600, "hour")
        let amount = value == value.rounded() ? String(Int(value)) : String(value)
        return (value * size, String(text[placeRange]), "In \(amount) \(name)\(value == 1 ? "" : "s")")
    }

    /// Qualified alternatives for a time question that failed only because a city name is
    /// ambiguous: "time in springfield" offers Springfield, MO, MA and IL. Runs only for queries
    /// shaped like time questions, so ordinary searches never load the city table.
    public static func suggestions(_ text: String, now: Date = Date(), localZone: TimeZone = .current,
                                   locale: Locale = .current) -> [(query: String, result: Result)] {
        guard text.utf8.count <= 256, evaluate(text, now: now, localZone: localZone, locale: locale) == nil else { return [] }
        let lowered = text.lowercased().split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
        let shaped = ["time in ", "now in ", "time diff ", "diff ", "time difference ", "difference "].contains(where: lowered.hasPrefix)
            || lowered.range(of: #"^(\d{4}-\d{2}-\d{2}\s+)?(\d{1,2}(:\d{2})?\s*(am|pm)?|noon|midnight)\s+\S"#, options: .regularExpression) != nil
        guard shaped else { return [] }
        let words = text.split(whereSeparator: { $0.isWhitespace }).map(String.init)
        let skip: Set<String> = ["time", "now", "in", "to", "diff", "difference", "with", "from", "at", "am", "pm"]
        for length in stride(from: min(3, words.count), through: 1, by: -1) {
            for start in 0...(words.count - length) {
                let span = words[start..<(start + length)]
                guard !span.contains(where: { skip.contains($0.lowercased()) || $0.contains(where: \.isNumber) }) else { continue }
                let alternatives = CityDirectory.shared.alternatives(span.joined(separator: " "))
                guard !alternatives.isEmpty else { continue }
                let found = alternatives.compactMap { alternative -> (query: String, result: Result)? in
                    let query = (words[..<start] + [alternative] + words[(start + length)...]).joined(separator: " ")
                    return evaluate(query, now: now, localZone: localZone, locale: locale).map { (query, $0) }
                }
                if !found.isEmpty { return found }
            }
        }
        return []
    }

    /// The place in "time diff Paris", "diff to Tokyo" or "time difference with New York".
    private static func differenceTarget(_ query: String) -> String? {
        guard let prefix = ["time difference ", "time diff ", "difference ", "diff "].first(where: query.hasPrefix) else { return nil }
        var name = String(query.dropFirst(prefix.count))
        if let joiner = ["to ", "with ", "in ", "from "].first(where: name.hasPrefix) { name.removeFirst(joiner.count) }
        return name.isEmpty ? nil : name
    }

    /// How far a place's clock is from the owner's right now: "1 hour ahead", "5 hours 30 minutes
    /// behind" or "Same time", tagged with the time there.
    private static func difference(_ zone: TimeZone, label: String, local: TimeZone, now: Date, locale: Locale) -> Result {
        let offset = zone.secondsFromGMT(for: now) - local.secondsFromGMT(for: now)
        let place = label.hasPrefix("in ") ? String(label.dropFirst(3)) : label
        let hours = abs(offset) / 3600, minutes = abs(offset) % 3600 / 60
        let span = [hours > 0 ? "\(hours) hour\(hours == 1 ? "" : "s")" : nil, minutes > 0 ? "\(minutes) minutes" : nil]
            .compactMap { $0 }.joined(separator: " ")
        let headline = offset == 0 ? "Same time" : "\(span) \(offset > 0 ? "ahead" : "behind")"
        let text = offset == 0 ? "\(place) is on your time" : "\(place) is \(headline)"
        let clock = clockText(now, zone: zone, locale: locale)
        let detail = label.hasPrefix("in ") ? "\(clock) \(label)" : "\(clock) \(place)"
        return Result(date: now, text: text, headline: headline, detail: detail, source: "Now")
    }

    private static func resolve(_ name: String, local: TimeZone) -> TimeZone? {
        if ["local", "here", "my time"].contains(name) { return local }
        if let hours = fixed[name] { return TimeZone(secondsFromGMT: hours * 3600) }
        if let identifier = regions[name]?.zone ?? cities[name]?.zone ?? identifiers[name] ?? zoneCities[name] {
            return TimeZone(identifier: identifier)
        }
        if let match = CityDirectory.shared.lookup(name) { return match.zone }
        if let airport = AirportDirectory.shared.lookup(name) { return airport.zone }
        return nil // CST/IST and broad geographic names are intentionally ambiguous.
    }

    private static func destinationLabel(_ name: String, zone: TimeZone, date: Date) -> String {
        if ["local", "here", "my time"].contains(name) { return "· your time" }
        if fixed[name] != nil { return name.uppercased() }
        if let region = regions[name] { return zone.isDaylightSavingTime(for: date) ? region.daylight : region.standard }
        if let city = cities[name] { return "in \(city.name)" }
        if identifiers[name] == nil, zoneCities[name] == nil {
            if let match = CityDirectory.shared.lookup(name) { return "in \(match.name)" }
            if let airport = AirportDirectory.shared.lookup(name) { return "in \(airport.city) (\(airport.code))" }
        }
        let city = zone.identifier.split(separator: "/").last.map(String.init)?.replacingOccurrences(of: "_", with: " ")
        return city.map { "in \($0)" } ?? zone.identifier
    }

    /// Weekday and date of an instant in the zone it was written in; the year appears only when it differs from now.
    static func describe(_ date: Date, in zone: TimeZone, now: Date, locale: Locale) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = zone
        formatter.locale = locale
        let sameYear = calendar.component(.year, from: date) == calendar.component(.year, from: now)
        formatter.setLocalizedDateFormatFromTemplate(sameYear ? "EEEEMMMMd" : "EEEEMMMMdyyyy")
        return formatter.string(from: date)
    }

    /// A day word's distance from the owner's local today: "friday" or "this friday" is the coming
    /// one, today included; "next friday" is the next one that is not today; "friday after next"
    /// is a week after that; "last friday" is the most recent one before today.
    private static func dayOffset(_ word: String, now: Date, calendar: Calendar) -> Int? {
        switch word {
        case "today", "tonight": return 0
        case "tomorrow": return 1
        case "yesterday": return -1
        default:
            let parts = word.split(separator: " ")
            guard let weekday = parts.last.flatMap({ weekdays[String($0)] }),
                  parts.count == 1 || ["next", "this", "last", "afternext"].contains(parts[0]) else { return nil }
            let ahead = (weekday - calendar.component(.weekday, from: now) + 7) % 7
            switch parts.count == 2 ? String(parts[0]) : "" {
            case "next": return ahead == 0 ? 7 : ahead
            case "afternext": return (ahead == 0 ? 7 : ahead) + 7
            case "last":
                let back = (calendar.component(.weekday, from: now) - weekday + 7) % 7
                return -(back == 0 ? 7 : back)
            default: return ahead
            }
        }
    }

    /// The clock as people say it: Midnight and Noon by name, otherwise the locale's hour and
    /// minute, which follows the owner's 24-hour setting.
    static func clockText(_ date: Date, zone: TimeZone, locale: Locale) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        let parts = calendar.dateComponents([.hour, .minute], from: date)
        if parts.hour == 0 && parts.minute == 0 { return "Midnight" }
        if parts.hour == 12 && parts.minute == 0 { return "Noon" }
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = zone
        formatter.locale = locale
        formatter.dateFormat = "h:mm a"
        return formatter.string(from: date)
    }

    /// A day word with a local time and no zone resolves a moment rather than converting one:
    /// "Tomorrow at 7:30 PM", tagged with its weekday, copied with its full date.
    private static func localResult(_ date: Date, offset: Int, zone: TimeZone, now: Date, locale: Locale) -> Result {
        let formatter = DateFormatter()
        formatter.timeZone = zone
        formatter.locale = locale
        formatter.setLocalizedDateFormatFromTemplate("EEEE")
        let weekday = formatter.string(from: date)
        let words = [0: "Today", 1: "Tomorrow", -1: "Yesterday"]
        var clock = clockText(date, zone: zone, locale: locale)
        if clock == "Midnight" || clock == "Noon" { clock = clock.lowercased() }
        let full = describe(date, in: zone, now: now, locale: locale)
        return Result(date: date, text: "\(full) at \(clock)", headline: "\(words[offset] ?? weekday) at \(clock)",
                      detail: words[offset] == nil ? (offset > 0 ? "In \(offset) days" : "\(-offset) days ago") : weekday, source: full)
    }

    private static func result(_ date: Date, zone: TimeZone, label: String,
                               baseline: DateComponents, explicitDate: Bool, source: String, now: Date, locale: Locale) -> Result {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = zone
        formatter.locale = locale
        let clock = clockText(date, zone: zone, locale: locale)
        let offset = calendar.date(from: baseline).flatMap {
            calendar.dateComponents([.day], from: $0, to: calendar.startOfDay(for: date)).day
        }
        var day: String?
        if explicitDate || ![0, 1, -1].contains(offset) {
            formatter.setLocalizedDateFormatFromTemplate("MMM d yyyy")
            day = formatter.string(from: date)
        } else if offset == 1 { day = "tomorrow" }
        else if offset == -1 { day = "yesterday" }
        let local = label == "· your time"
        let when: String
        switch offset {
        case 0: when = "Today"
        case 1: when = "Tomorrow"
        case -1: when = "Yesterday"
        default: when = describe(date, in: zone, now: now, locale: locale)
        }
        return Result(date: date, text: "\(clock) \(label)" + (day.map { " · " + $0 } ?? ""),
                      headline: local ? clock : "\(clock) \(label)",
                      detail: local ? "Your time · " + when : when, source: source)
    }
}
