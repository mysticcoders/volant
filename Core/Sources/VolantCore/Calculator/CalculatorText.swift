import Foundation

/// Locale-following pieces shared by calculator answers. Counts of calendar and clock units use
/// Foundation's own unit words and plural rules for the locale ("3 days", "1 Woche", "36.600 Tage"),
/// fractional durations keep the calculator's precision with the locale's decimal separator, and
/// formatter spaces become ordinary ones so a copied answer behaves like typed text.
enum CalculatorText {
    enum Unit {
        case second, minute, hour, day, week, year
    }

    /// Replaces the no-break and narrow no-break spaces formatters insert with ordinary spaces.
    static func plain(_ text: String) -> String {
        text.replacingOccurrences(of: "\u{00A0}", with: " ").replacingOccurrences(of: "\u{202F}", with: " ")
    }

    /// A whole count with the locale's unit word and grouping: "1,992 hours", "3 Wochen".
    static func count(_ value: Int, _ unit: Unit, locale: Locale) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = locale
        let formatter = DateComponentsFormatter()
        formatter.calendar = calendar
        formatter.unitsStyle = .full
        formatter.maximumUnitCount = 1
        var components = DateComponents()
        switch unit {
        case .second: components.second = value; formatter.allowedUnits = [.second]
        case .minute: components.minute = value; formatter.allowedUnits = [.minute]
        case .hour: components.hour = value; formatter.allowedUnits = [.hour]
        case .day: components.day = value; formatter.allowedUnits = [.day]
        case .week: components.weekOfMonth = value; formatter.allowedUnits = [.weekOfMonth]
        case .year: components.year = value; formatter.allowedUnits = [.year]
        }
        return plain(formatter.string(from: components) ?? String(value))
    }

    /// A duration that may be fractional, such as "3.25 hours" or "3,25 Stunden": whole values read
    /// as `count`, others with up to ten decimals, as `Calculator.format` writes them.
    static func amount(_ value: Double, _ unit: Unit, locale: Locale) -> String {
        if value == value.rounded(), abs(value) < 1e15 { return count(Int(value), unit, locale: locale) }
        let durations: [Unit: UnitDuration] = [.second: .seconds, .minute: .minutes, .hour: .hours]
        guard let duration = durations[unit] else {
            let number = Calculator.format(value, locale: locale)
            return String(localized: "\(number, format: .verbatim) days", table: "Core",
                          comment: "Calculator duration answer with a fractional number of days, such as 1.5 days")
        }
        let number = NumberFormatter()
        number.locale = locale
        number.numberStyle = .decimal
        number.maximumFractionDigits = 10
        number.usesGroupingSeparator = false
        let formatter = MeasurementFormatter()
        formatter.locale = locale
        formatter.unitStyle = .long
        formatter.unitOptions = .providedUnit
        formatter.numberFormatter = number
        return plain(formatter.string(from: Measurement(value: value, unit: duration)))
    }

    /// Workdays, which no Foundation unit names: "54 workdays", or "6.875 workdays" for a fraction.
    static func workdays(_ value: Double, locale: Locale) -> String {
        if value == value.rounded(), abs(value) < 1e15 {
            let whole = Int(value)
            return String(localized: "\(whole, specifier: "%lld") workdays", table: "Core",
                          comment: "Calculator answer: a number of working days (Monday to Friday, minus holidays)")
        }
        let number = Calculator.format(value, locale: locale)
        return String(localized: "\(number, format: .verbatim) workdays", table: "Core",
                      comment: "Calculator answer: a fractional number of eight-hour working days, such as 6.875")
    }

    /// Two dates or clock times as a range: "Monday, October 5 to Sunday, October 11".
    static func range(_ start: String, _ end: String) -> String {
        String(localized: "\(start, format: .verbatim) to \(end, format: .verbatim)", table: "Core",
               comment: "Calculator answer detail: a range from the first date or time to the second")
    }

    /// A date with a time of day: "Friday, October 2 at 7:30 PM".
    static func at(_ day: String, _ clock: String) -> String {
        String(localized: "\(day, format: .verbatim) at \(clock, format: .verbatim)", table: "Core",
               comment: "Calculator answer: a date or day word, then a time of day on it")
    }
}
