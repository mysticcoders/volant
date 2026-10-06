import Foundation

/// Date and duration questions, answered in the owner's local calendar: day words on their own
/// ("today", "now"), counting ("days until 31 Mar", "days since Jan 1", "days between Jan 1 and
/// Mar 1"), offsets ("in 3 weeks", "35 days ago", "monday in 3 weeks"), arithmetic ("August 5 + 5",
/// "3:45pm + 5"), timespans ("145 mins to timespan"), summed durations ("2h 20min + 55min in
/// hours"), workdays ("workdays until Dec 25", "in 10 business days"), named holidays ("days until
/// christmas", "easter 2027"), "next friday", ISO 8601 timestamps and Unix time.
///
/// "this friday" is the coming Friday, today included; "next friday" is the next one that is not
/// today, one to seven days ahead. Workdays are Monday to Friday; public holidays are not
/// subtracted. Holidays are the US and widely shared ones: Christmas and its eve, New Year's Day
/// and Eve, Halloween, Valentine's Day, St Patrick's Day, Independence Day, US Thanksgiving (fourth
/// Thursday of November) and Western Easter.
///
/// Hours and minutes are elapsed time; days and longer are calendar steps, so a daylight-saving
/// change never shifts "in 2 days" off midnight. A plain number after a date means days and after
/// a clock time means hours. A date without a year means its next occurrence after "until", its
/// last after "since", and this year elsewhere. Numeric dates such as 12/25 are left alone, since
/// their order depends on locale.
public enum DateCalculator {
    enum Step: Equatable {
        case seconds(Double)
        case days(Int), workdays(Int), months(Int), years(Int)
    }

    private enum DateWord {
        case day(Date)
        case calendar(month: Int, day: Int, year: Int?)
        case holiday(Holiday, year: Int?)
    }

    enum Holiday: String {
        case christmas, christmasEve, newYear, newYearsEve, halloween, valentines, stPatricks, independence, thanksgiving, easter

        /// Month and day of the holiday in `year`.
        func date(in year: Int) -> (month: Int, day: Int) {
            switch self {
            case .christmas: return (12, 25)
            case .christmasEve: return (12, 24)
            case .newYear: return (1, 1)
            case .newYearsEve: return (12, 31)
            case .halloween: return (10, 31)
            case .valentines: return (2, 14)
            case .stPatricks: return (3, 17)
            case .independence: return (7, 4)
            case .thanksgiving:
                let first = DateCalculator.weekday(year: year, month: 11, day: 1)
                return (11, 1 + (5 - first + 7) % 7 + 21)
            case .easter: return DateCalculator.easter(year)
            }
        }
    }

    private static let holidays: [String: Holiday] = [
        "christmas": .christmas, "christmas day": .christmas, "xmas": .christmas, "christmas eve": .christmasEve,
        "new year": .newYear, "new years": .newYear, "new years day": .newYear, "new year day": .newYear,
        "new years eve": .newYearsEve, "new year eve": .newYearsEve, "halloween": .halloween,
        "valentines": .valentines, "valentines day": .valentines, "valentine day": .valentines,
        "st patricks": .stPatricks, "st patricks day": .stPatricks, "saint patricks day": .stPatricks,
        "independence day": .independence, "4 of july": .independence, "fourth of july": .independence, "july 4": .independence,
        "thanksgiving": .thanksgiving, "thanksgiving day": .thanksgiving, "easter": .easter, "easter sunday": .easter
    ]

    private struct Context {
        let now: Date
        let calendar: Calendar
        let locale: Locale
        var today: Date { calendar.startOfDay(for: now) }
    }

    private static let months: [String: Int] = [
        "january": 1, "jan": 1, "february": 2, "feb": 2, "march": 3, "mar": 3, "april": 4, "apr": 4, "may": 5,
        "june": 6, "jun": 6, "july": 7, "jul": 7, "august": 8, "aug": 8, "september": 9, "sep": 9, "sept": 9,
        "october": 10, "oct": 10, "november": 11, "nov": 11, "december": 12, "dec": 12
    ]
    private static let weekdays: [String: Int] = [
        "sunday": 1, "sun": 1, "monday": 2, "mon": 2, "tuesday": 3, "tue": 3, "tues": 3, "wednesday": 4, "wed": 4,
        "thursday": 5, "thu": 5, "thurs": 5, "friday": 6, "fri": 6, "saturday": 7, "sat": 7
    ]

    public static func evaluate(_ text: String, now: Date = Date(), localZone: TimeZone = .current,
                                locale: Locale = .current) -> CalculationAnswer? {
        guard text.utf8.count <= 256 else { return nil }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = localZone
        calendar.locale = locale
        let context = Context(now: now, calendar: calendar, locale: locale)
        let input = text.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
        if let stamp = timestamp(input, context) { return stamp }
        let words = normalize(text)
        guard !words.isEmpty else { return nil }
        return unix(words, input: input, context)
            ?? dayAlone(words, input: input, context)
            ?? counting(words, input: input, context)
            ?? timespan(words, input: input, context)
            ?? durationSum(words, input: input, context)
            ?? offset(words, input: input, context)
            ?? weekdayInWeeks(words, input: input, context)
            ?? arithmetic(words, input: input, context)
    }

    /// Lowercase words with commas, apostrophes and ordinal suffixes removed, numbers split from
    /// units they touch ("90min", "31st", "3:45pm"), and "business days" or "working days" read as
    /// workdays.
    static func normalize(_ text: String) -> [String] {
        var value = text.lowercased().replacingOccurrences(of: ",", with: " ")
        value = value.replacingOccurrences(of: #"['’]"#, with: "", options: .regularExpression)
        value = value.replacingOccurrences(of: #"\b(business|working)\s+(day|days)\b"#, with: "workdays", options: .regularExpression)
        value = value.replacingOccurrences(of: #"\b(\d+)(st|nd|rd|th)\b"#, with: "$1", options: .regularExpression)
        value = value.replacingOccurrences(of: #"(\d)([a-z])"#, with: "$1 $2", options: .regularExpression)
        value = value.replacingOccurrences(of: "+", with: " + ")
        value = value.replacingOccurrences(of: #"(?<!\d)-|-(?!\d)"#, with: " - ", options: .regularExpression)
        return value.split(whereSeparator: { $0.isWhitespace }).map(String.init)
    }

    /// "now", "today", "tomorrow", "yesterday", or "next friday" and "this friday" on their own.
    /// Holiday names alone are left to search, so "christmas" still finds apps and files.
    private static func dayAlone(_ words: [String], input: String, _ c: Context) -> CalculationAnswer? {
        if words.count == 2, ["next", "this"].contains(words[0]), case .day(let day)? = dateWord(words[...], c) {
            let text = dateText(day, c)
            return CalculationAnswer(input: input, inputDetail: nil, result: text, resultDetail: relative(day, c), copyText: text)
        }
        guard words.count == 1 else { return nil }
        if words[0] == "now" {
            let full = dateText(c.now, c)
            let clock = TimeCalculator.clockText(c.now, zone: c.calendar.timeZone, locale: c.locale)
            return CalculationAnswer(input: input, inputDetail: nil, result: clock, resultDetail: full, copyText: "\(full) at \(clock)")
        }
        guard ["today", "tomorrow", "yesterday"].contains(words[0]), case .day(let day)? = dateWord(words[...], c) else { return nil }
        let text = dateText(day, c)
        return CalculationAnswer(input: input, inputDetail: nil, result: text, resultDetail: relative(day, c), copyText: text)
    }

    /// An ISO 8601 timestamp shown in local time: "2024-03-15T14:30:00Z", "…+02:00", fractional
    /// seconds, or "2024-03-15T14:30" without a zone, which is already local.
    private static func timestamp(_ input: String, _ c: Context) -> CalculationAnswer? {
        guard input.count >= 16, input.range(of: #"^\d{4}-\d{2}-\d{2}[Tt ]\d{2}:\d{2}"#, options: .regularExpression) != nil else { return nil }
        let text = input.uppercased().replacingOccurrences(of: " ", with: "T")
        var date: Date?
        for options: ISO8601DateFormatter.Options in [[.withInternetDateTime], [.withInternetDateTime, .withFractionalSeconds]] where date == nil {
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = options
            date = formatter.date(from: text)
        }
        if date == nil {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.timeZone = c.calendar.timeZone
            for format in ["yyyy-MM-dd'T'HH:mm:ss", "yyyy-MM-dd'T'HH:mm"] where date == nil {
                formatter.dateFormat = format
                date = formatter.date(from: text)
            }
        }
        guard let date else { return nil }
        return moment(date, input: input, inputDetail: relative(date, c), c)
    }

    /// Unix time: "unix 1700000000", "1700000000 unix" (milliseconds when 13 digits), and
    /// "unix now" or "now in unix" for the current value.
    private static func unix(_ words: [String], input: String, _ c: Context) -> CalculationAnswer? {
        if words == ["unix", "now"] || words == ["now", "in", "unix"] || words == ["unix", "time"] {
            let seconds = String(Int(c.now.timeIntervalSince1970))
            return CalculationAnswer(input: input, inputDetail: nil, result: seconds, resultDetail: "Seconds since 1970", copyText: seconds)
        }
        guard words.count == 2, words.contains("unix") || words.contains("epoch"),
              let digits = words.first(where: { $0 != "unix" && $0 != "epoch" }),
              digits.allSatisfy(\.isNumber), (9...13).contains(digits.count), let value = Double(digits) else { return nil }
        let date = Date(timeIntervalSince1970: digits.count == 13 ? value / 1000 : value)
        return moment(date, input: input, inputDetail: digits.count == 13 ? "Milliseconds" : "Seconds", c)
    }

    /// A moment in local time: the clock, tagged with its date, copied with both.
    private static func moment(_ date: Date, input: String, inputDetail: String?, _ c: Context) -> CalculationAnswer {
        let clock = TimeCalculator.clockText(date, zone: c.calendar.timeZone, locale: c.locale)
        let day = dateText(date, c)
        return CalculationAnswer(input: input, inputDetail: inputDetail, result: clock, resultDetail: day, copyText: "\(day) at \(clock)")
    }

    /// "days until 31 Mar", "weeks since Jan 1", "days between Jan 1 and Mar 1", "workdays until
    /// christmas". Workdays count Monday to Friday after the start, up to and including the end.
    private static func counting(_ words: [String], input: String, _ c: Context) -> CalculationAnswer? {
        guard words.count >= 3, let unit = ["days": 1, "day": 1, "weeks": 7, "week": 7, "workdays": 0, "workday": 0][words[0]] else { return nil }
        let start: Date, end: Date
        switch words[1] {
        case "until", "till", "to":
            guard let target = date(words[2...], c, direction: 1) else { return nil }
            (start, end) = (c.today, target)
        case "since", "from":
            guard let target = date(words[2...], c, direction: -1) else { return nil }
            (start, end) = (target, c.today)
        case "between":
            guard let and = words.firstIndex(of: "and"), and > 2,
                  let first = date(words[2..<and], c, direction: 0), let second = date(words[(and + 1)...], c, direction: 0) else { return nil }
            (start, end) = (first, second)
        default: return nil
        }
        guard let days = c.calendar.dateComponents([.day], from: start, to: end).day else { return nil }
        let span: String
        if unit == 0 {
            guard abs(days) <= 36_600 else { return nil }
            let (from, to) = days < 0 ? (end, start) : (start, end)
            span = count(workdays(after: from, through: to, c.calendar), "workday")
        } else {
            span = unit == 7 ? weeksText(abs(days)) : count(abs(days), "day")
        }
        let text = days < 0 ? span + " ago" : span
        let anchor = words[1] == "between" ? nil : (words[1] == "since" || words[1] == "from" ? start : end)
        return CalculationAnswer(input: input, inputDetail: nil, result: text,
                                 resultDetail: anchor.map { dateText($0, c) } ?? "\(dateText(start, c)) to \(dateText(end, c))", copyText: text)
    }

    /// "145 mins to timespan", "100000 s as duration".
    private static func timespan(_ words: [String], input: String, _ c: Context) -> CalculationAnswer? {
        guard words.count >= 4, ["to", "in", "as"].contains(words[words.count - 2]) || words.suffix(3) == ["to", "time", "span"] else { return nil }
        let target = words.last == "span" ? "timespan" : words.last!
        guard ["timespan", "duration"].contains(target) else { return nil }
        let amount = words.last == "span" ? words.dropLast(3) : words.dropLast(2)
        let seconds: Double
        switch quantity(amount)?.1 {
        case .seconds(let value)?: seconds = value
        case .days(let value)?: seconds = Double(value) * 86_400
        default: return nil
        }
        guard seconds > 0 else { return nil }
        let text = spanText(seconds)
        return CalculationAnswer(input: input, inputDetail: nil, result: text, resultDetail: nil, copyText: text)
    }

    /// "2h 20min + 55min" gives a timespan, and "… in hours" a decimal: elapsed durations added and
    /// subtracted. Needs more than a single quantity, which `UnitConverter` already handles.
    private static func durationSum(_ words: [String], input: String, _ c: Context) -> CalculationAnswer? {
        var body = words[...], target: (seconds: Double, name: String)?
        if words.count >= 3, ["in", "to", "as"].contains(words[words.count - 2]) {
            let units: [String: (Double, String)] = ["seconds": (1, "second"), "second": (1, "second"), "s": (1, "second"),
                                                     "minutes": (60, "minute"), "minute": (60, "minute"), "min": (60, "minute"),
                                                     "hours": (3600, "hour"), "hour": (3600, "hour"), "h": (3600, "hour"),
                                                     "days": (86_400, "day"), "day": (86_400, "day")]
            if words.last == "timespan" || words.last == "duration" { body = words.dropLast(2) }
            else if let unit = units[words.last!] { target = unit; body = words.dropLast(2) }
        }
        var total = 0.0, sign = 1.0, terms = 0, pairs = 0, index = body.startIndex
        while index < body.endIndex {
            let word = body[index]
            if word == "+" || word == "-" {
                guard terms > 0 else { return nil }
                sign = word == "+" ? 1 : -1
                index += 1
                continue
            }
            guard index + 1 < body.endIndex, let (_, step) = quantity(body[index...(index + 1)]) else { return nil }
            switch step {
            case .seconds(let value): total += sign * value
            case .days(let value): total += sign * Double(value) * 86_400
            default: return nil
            }
            if index == body.startIndex || ["+", "-"].contains(body[index - 1]) { terms += 1 }
            pairs += 1
            index += 2
        }
        guard pairs >= 2, total > 0 else { return nil }
        let text: String
        if let target {
            let value = (total / target.seconds * 10_000).rounded() / 10_000
            text = "\(Calculator.format(value, locale: c.locale)) \(target.name)\(value == 1 ? "" : "s")"
        } else {
            text = spanText(total)
        }
        return CalculationAnswer(input: input, inputDetail: nil, result: text, resultDetail: nil, copyText: text)
    }

    /// "in 3 weeks", "10 days from now", "35 days ago", "in 4 hours".
    private static func offset(_ words: [String], input: String, _ c: Context) -> CalculationAnswer? {
        var amount: ArraySlice<String>, sign = 1
        if words.first == "in" { amount = words.dropFirst() }
        else if words.suffix(2) == ["from", "now"] { amount = words.dropLast(2) }
        else if words.last == "ago" { amount = words.dropLast(); sign = -1 }
        else { return nil }
        guard let (_, step) = quantity(amount) else { return nil }
        return answer(applying: step, sign: sign, to: c.now, input: input, inputDetail: nil, c)
    }

    /// "monday in 3 weeks": that weekday in the week (Monday to Sunday) three weeks from now.
    private static func weekdayInWeeks(_ words: [String], input: String, _ c: Context) -> CalculationAnswer? {
        guard words.count >= 3, let weekday = weekdays[words[0]], words[1] == "in",
              let (_, step) = quantity(words[2...]), case .days(let days) = step, days % 7 == 0,
              let ahead = c.calendar.date(byAdding: .day, value: days, to: c.today) else { return nil }
        let mondayOffset = (c.calendar.component(.weekday, from: ahead) + 5) % 7
        guard let monday = c.calendar.date(byAdding: .day, value: -mondayOffset, to: ahead),
              let target = c.calendar.date(byAdding: .day, value: (weekday + 5) % 7, to: monday) else { return nil }
        let text = dateText(target, c)
        return CalculationAnswer(input: input, inputDetail: nil, result: text, resultDetail: relative(target, c), copyText: text)
    }

    /// "<date> + 5" (days), "<date> - 2 weeks", "3:45pm + 5" (hours), "9am + 90 min".
    private static func arithmetic(_ words: [String], input: String, _ c: Context) -> CalculationAnswer? {
        guard let operatorIndex = words.lastIndex(where: { $0 == "+" || $0 == "-" }), operatorIndex > 0 else { return nil }
        let base = words[..<operatorIndex], amount = words[(operatorIndex + 1)...]
        let sign = words[operatorIndex] == "+" ? 1 : -1
        if let start = clock(base, c) {
            let step = amount.count == 1 ? Double(amount.first!).map { Step.seconds($0 * 3600) } : quantity(amount)?.1
            guard let step, case .seconds = step else { return nil }
            return answer(applying: step, sign: sign, to: start, input: input,
                          inputDetail: TimeCalculator.clockText(start, zone: c.calendar.timeZone, locale: c.locale), c)
        }
        guard let start = date(base, c, direction: 0) else { return nil }
        let step = amount.count == 1 ? Int(amount.first!).map { Step.days($0) } : quantity(amount)?.1
        guard let step else { return nil }
        if case .seconds = step { return nil }
        return answer(applying: step, sign: sign, to: start, input: input, inputDetail: dateText(start, c), c)
    }

    private static func answer(applying step: Step, sign: Int, to start: Date, input: String, inputDetail: String?, _ c: Context) -> CalculationAnswer? {
        guard let target = apply(step, sign: sign, to: start, c) else { return nil }
        if case .seconds = step {
            let clock = TimeCalculator.clockText(target, zone: c.calendar.timeZone, locale: c.locale)
            let day = relative(c.calendar.startOfDay(for: target), c)
            let copy = day == "Today" ? clock : "\(dateText(target, c)) at \(clock)"
            return CalculationAnswer(input: input, inputDetail: inputDetail, result: clock, resultDetail: day, copyText: copy)
        }
        let text = dateText(target, c)
        return CalculationAnswer(input: input, inputDetail: inputDetail, result: text, resultDetail: relative(target, c), copyText: text)
    }

    static func apply(_ step: Step, sign: Int, to date: Date, _ calendar: Calendar) -> Date? {
        switch step {
        case .seconds(let value): return date.addingTimeInterval(Double(sign) * value)
        case .days(let value): return calendar.date(byAdding: .day, value: sign * value, to: date)
        case .workdays(let value):
            guard value <= 26_000 else { return nil }
            var day = date, remaining = value
            while remaining > 0 {
                guard let next = calendar.date(byAdding: .day, value: sign, to: day) else { return nil }
                day = next
                if !calendar.isDateInWeekend(day) { remaining -= 1 }
            }
            return day
        case .months(let value): return calendar.date(byAdding: .month, value: sign * value, to: date)
        case .years(let value): return calendar.date(byAdding: .year, value: sign * value, to: date)
        }
    }

    private static func apply(_ step: Step, sign: Int, to date: Date, _ c: Context) -> Date? {
        apply(step, sign: sign, to: date, c.calendar)
    }

    private static func dateText(_ date: Date, _ c: Context) -> String {
        TimeCalculator.describe(date, in: c.calendar.timeZone, now: c.now, locale: c.locale)
    }

    /// Today, Tomorrow, Yesterday, otherwise "In 21 days" or "35 days ago".
    private static func relative(_ date: Date, _ c: Context) -> String {
        guard let days = c.calendar.dateComponents([.day], from: c.today, to: c.calendar.startOfDay(for: date)).day else { return "" }
        switch days {
        case 0: return "Today"
        case 1: return "Tomorrow"
        case -1: return "Yesterday"
        case let n where n > 0: return "In \(count(n, "day"))"
        default: return "\(count(-days, "day")) ago"
        }
    }

    /// Monday-to-Friday days after `start`, up to and including `end`.
    private static func workdays(after start: Date, through end: Date, _ calendar: Calendar) -> Int {
        var total = 0, day = start
        while let next = calendar.date(byAdding: .day, value: 1, to: day), next <= end {
            day = next
            if !calendar.isDateInWeekend(day) { total += 1 }
        }
        return total
    }

    /// Weekday of a Gregorian date, Sunday being 1, by Zeller's congruence.
    static func weekday(year: Int, month: Int, day: Int) -> Int {
        let m = month < 3 ? month + 12 : month, y = month < 3 ? year - 1 : year
        let h = (day + 13 * (m + 1) / 5 + y + y / 4 - y / 100 + y / 400) % 7
        return (h + 6) % 7 + 1
    }

    /// Western (Gregorian) Easter Sunday by the anonymous Gregorian algorithm.
    static func easter(_ year: Int) -> (month: Int, day: Int) {
        let a = year % 19, b = year / 100, c = year % 100, d = b / 4, e = b % 4
        let f = (b + 8) / 25, g = (b - f + 1) / 3, h = (19 * a + b - d - g + 15) % 30
        let i = c / 4, k = c % 4, l = (32 + 2 * e + 2 * i - h - k) % 7, m = (a + 11 * h + 22 * l) / 451
        return ((h + l - 7 * m + 114) / 31, (h + l - 7 * m + 114) % 31 + 1)
    }

    private static func count(_ value: Int, _ unit: String) -> String {
        "\(value.formatted()) \(unit)\(abs(value) == 1 ? "" : "s")"
    }

    private static func weeksText(_ days: Int) -> String {
        let weeks = days / 7, rest = days % 7
        return rest == 0 ? count(weeks, "week") : "\(count(weeks, "week")) \(count(rest, "day"))"
    }

    /// Days, hours, minutes and seconds, largest first, skipping empty parts.
    static func spanText(_ seconds: Double) -> String {
        var remaining = Int(seconds.rounded())
        var parts: [String] = []
        for (size, unit) in [(86_400, "day"), (3600, "hour"), (60, "minute"), (1, "second")] where remaining >= size {
            parts.append(count(remaining / size, unit))
            remaining %= size
        }
        return parts.isEmpty ? "0 seconds" : parts.joined(separator: " ")
    }

    /// "3 weeks", "a week", "90 min", "1.5 hours". Calendar steps need whole numbers.
    static func quantity(_ words: ArraySlice<String>) -> (Double, Step)? {
        guard words.count == 2, let first = words.first, let unit = words.last else { return nil }
        guard let number = first == "a" || first == "an" ? 1 : Double(first), number >= 0 else { return nil }
        let whole = number == number.rounded() ? Int(number) : nil
        switch unit {
        case "s", "sec", "secs", "second", "seconds": return (number, .seconds(number))
        case "m", "min", "mins", "minute", "minutes": return (number, .seconds(number * 60))
        case "h", "hr", "hrs", "hour", "hours": return (number, .seconds(number * 3600))
        case "d", "day", "days": return whole.map { (number, .days($0)) }
        case "w", "wk", "wks", "week", "weeks": return whole.map { (number, .days($0 * 7)) }
        case "mo", "month", "months": return whole.map { (number, .months($0)) }
        case "y", "yr", "yrs", "year", "years": return whole.map { (number, .years($0)) }
        case "workday", "workdays": return whole.map { (number, .workdays($0)) }
        default: return nil
        }
    }

    /// A clock time today: "3:45 pm", "15:45", "9 am".
    private static func clock(_ words: ArraySlice<String>, _ c: Context) -> Date? {
        guard (1...2).contains(words.count), let first = words.first else { return nil }
        let meridiem = words.count == 2 ? words.last : nil
        guard meridiem == nil || meridiem == "am" || meridiem == "pm" else { return nil }
        let pieces = first.split(separator: ":", omittingEmptySubsequences: false)
        guard (1...2).contains(pieces.count), var hour = Int(pieces[0]) else { return nil }
        let minute = pieces.count == 2 ? Int(pieces[1]) : 0
        guard let minute, (0..<60).contains(minute), pieces.count == 2 || meridiem != nil else { return nil }
        if let meridiem {
            guard (1...12).contains(hour) else { return nil }
            hour = hour % 12 + (meridiem == "pm" ? 12 : 0)
        } else {
            guard hour < 24 else { return nil }
        }
        return c.calendar.date(bySettingHour: hour, minute: minute, second: 0, of: c.today)
    }

    /// A date at the start of its day. `direction` picks the next (1), last (-1) or this-year (0)
    /// occurrence of a date written without a year.
    private static func date(_ words: ArraySlice<String>, _ c: Context, direction: Int) -> Date? {
        switch dateWord(words, c) {
        case .day(let day)?: return day
        case .holiday(let holiday, let year)?:
            let thisYear = c.calendar.component(.year, from: c.now)
            func make(_ year: Int) -> Date? {
                let (month, day) = holiday.date(in: year)
                return c.calendar.date(from: DateComponents(year: year, month: month, day: day))
            }
            if let year { return make(year) }
            guard let candidate = make(thisYear) else { return nil }
            if direction > 0 && candidate < c.today { return make(thisYear + 1) }
            if direction < 0 && candidate > c.today { return make(thisYear - 1) }
            return candidate
        case .calendar(let month, let day, let year)?:
            let thisYear = c.calendar.component(.year, from: c.now)
            func make(_ year: Int) -> Date? {
                let components = DateComponents(year: year, month: month, day: day)
                guard let date = c.calendar.date(from: components),
                      c.calendar.dateComponents([.year, .month, .day], from: date) == components else { return nil }
                return date
            }
            if let year { return make(year) }
            guard let candidate = make(thisYear) else { return nil }
            if direction > 0 && candidate < c.today { return make(thisYear + 1) }
            if direction < 0 && candidate > c.today { return make(thisYear - 1) }
            return candidate
        case nil: return nil
        }
    }

    private static func dateWord(_ words: ArraySlice<String>, _ c: Context) -> DateWord? {
        let parts = Array(words)
        if let last = parts.last, last.count == 4, let year = Int(last), parts.count > 1,
           let holiday = holidays[parts.dropLast().joined(separator: " ")] {
            return .holiday(holiday, year: year)
        }
        if let holiday = holidays[parts.joined(separator: " ")] { return .holiday(holiday, year: nil) }
        if parts.count == 2, ["next", "this"].contains(parts[0]), let weekday = weekdays[parts[1]] {
            var ahead = (weekday - c.calendar.component(.weekday, from: c.now) + 7) % 7
            if parts[0] == "next" && ahead == 0 { ahead = 7 }
            return c.calendar.date(byAdding: .day, value: ahead, to: c.today).map(DateWord.day)
        }
        if parts.count == 1 {
            switch parts[0] {
            case "today": return .day(c.today)
            case "tomorrow": return c.calendar.date(byAdding: .day, value: 1, to: c.today).map(DateWord.day)
            case "yesterday": return c.calendar.date(byAdding: .day, value: -1, to: c.today).map(DateWord.day)
            default: break
            }
            if let weekday = weekdays[parts[0]] {
                let ahead = (weekday - c.calendar.component(.weekday, from: c.now) + 7) % 7
                return c.calendar.date(byAdding: .day, value: ahead, to: c.today).map(DateWord.day)
            }
            let fields = parts[0].split(separator: "-").compactMap { Int($0) }
            if parts[0].range(of: #"^\d{4}-\d{2}-\d{2}$"#, options: .regularExpression) != nil, fields.count == 3 {
                return .calendar(month: fields[1], day: fields[2], year: fields[0])
            }
            return nil
        }
        guard (2...3).contains(parts.count) else { return nil }
        let year = parts.count == 3 ? Int(parts[2]) : nil
        guard parts.count == 2 || (year.map { (1...9999).contains($0) } ?? false) else { return nil }
        if let month = months[parts[0]], let day = Int(parts[1]) { return .calendar(month: month, day: day, year: year) }
        if let month = months[parts[1]], let day = Int(parts[0]) { return .calendar(month: month, day: day, year: year) }
        return nil
    }
}
