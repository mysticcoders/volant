import Foundation

/// A weather forecast a list extension attaches to one row, which the launcher draws as a card instead
/// of a plain row: the place and its current conditions, the day's high and low, an hourly strip and a
/// daily strip. Temperatures are Celsius and Volant shows them in the owner's units. Times are the
/// place's own wall-clock times, `2026-11-14T10:00` and `2026-11-14`, so Volant formats them without
/// converting time zones. It only describes what to draw, so it needs no permission; symbols come from
/// `ExtensionItemSymbol`, and anything Volant does not know is dropped.
public struct ExtensionItemForecast: Codable, Hashable, Sendable {
    public static let maximumHours = 24
    public static let maximumDays = 10
    public static let maximumPlaceLength = 80
    public static let maximumConditionLength = 40
    /// Celsius values outside the coldest and hottest temperatures ever measured, with some margin.
    public static let plausibleCelsius: ClosedRange<Double> = -100...70

    public var place: String
    public var condition: String?
    public var symbol: String?
    public var temperature: Double?
    public var high: Double?
    public var low: Double?
    public var hours: [Hour]?
    public var days: [Day]?

    public init(place: String, condition: String? = nil, symbol: String? = nil, temperature: Double? = nil, high: Double? = nil,
                low: Double? = nil, hours: [Hour]? = nil, days: [Day]? = nil) {
        self.place = place; self.condition = condition; self.symbol = symbol; self.temperature = temperature
        self.high = high; self.low = low; self.hours = hours; self.days = days
    }

    /// One hour of the strip; the first is the current hour, labeled Now.
    public struct Hour: Codable, Hashable, Sendable {
        public var time: String
        public var temperature: Double
        public var symbol: String?
        public init(time: String, temperature: Double, symbol: String? = nil) { self.time = time; self.temperature = temperature; self.symbol = symbol }
    }

    /// One day of the week strip; the first is today at the place.
    public struct Day: Codable, Hashable, Sendable {
        public var date: String
        public var high: Double
        public var low: Double
        public var symbol: String?
        public init(date: String, high: Double, low: Double, symbol: String? = nil) { self.date = date; self.high = high; self.low = low; self.symbol = symbol }
    }

    /// Trims the text, drops unknown symbols, implausible temperatures and hours or days whose time
    /// does not parse, and keeps at most 24 hours and 10 days. A forecast with no place, or with
    /// nothing to show, is dropped and the row draws as an ordinary row.
    func sanitized() -> ExtensionItemForecast? {
        let place = Self.line(place, limit: Self.maximumPlaceLength)
        guard !place.isEmpty else { return nil }
        let hours = (hours ?? []).compactMap { hour -> Hour? in
            guard Self.hourDate(hour.time) != nil, let temperature = Self.plausible(hour.temperature) else { return nil }
            return Hour(time: hour.time, temperature: temperature, symbol: Self.knownSymbol(hour.symbol))
        }.prefix(Self.maximumHours)
        let days = (days ?? []).compactMap { day -> Day? in
            guard Self.dayDate(day.date) != nil, let high = Self.plausible(day.high), let low = Self.plausible(day.low) else { return nil }
            return Day(date: day.date, high: high, low: low, symbol: Self.knownSymbol(day.symbol))
        }.prefix(Self.maximumDays)
        let temperature = temperature.flatMap(Self.plausible)
        guard temperature != nil || !hours.isEmpty || !days.isEmpty else { return nil }
        let condition = condition.map { Self.line($0, limit: Self.maximumConditionLength) }.flatMap { $0.isEmpty ? nil : $0 }
        return ExtensionItemForecast(place: place, condition: condition, symbol: Self.knownSymbol(symbol), temperature: temperature,
                                     high: high.flatMap(Self.plausible), low: low.flatMap(Self.plausible),
                                     hours: hours.isEmpty ? nil : Array(hours), days: days.isEmpty ? nil : Array(days))
    }

    /// Whole degrees in the owner's units, such as "13°" or "55°", from Celsius. `units` is what
    /// `ExtensionNetwork.units(for:)` reports: "us" for Fahrenheit, anything else for Celsius.
    public static func degrees(_ celsius: Double, units: String = ExtensionNetwork.units()) -> String {
        let value = units == "us" ? celsius * 9 / 5 + 32 : celsius
        let rounded = Int(value.rounded())
        return "\(rounded == 0 ? 0 : rounded)°"
    }

    /// The hour label for the strip in the owner's clock style, such as "10 AM" or "10"; the first
    /// hour reads Now.
    public static func hourLabel(_ hour: Hour, index: Int, locale: Locale = .current) -> String {
        if index == 0 { return String(localized: "Now", table: "Core", comment: "Weather card: the current hour in the hourly forecast") }
        guard let date = hourDate(hour.time) else { return hour.time }
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.timeZone = utc
        formatter.setLocalizedDateFormatFromTemplate("j")
        return formatter.string(from: date)
    }

    /// The day label for the week strip, such as "Sat"; the first day reads Today.
    public static func dayLabel(_ day: Day, index: Int, locale: Locale = .current) -> String {
        if index == 0 { return String(localized: "Today", table: "Core", comment: "Weather card: the first day of the week's forecast") }
        guard let date = dayDate(day.date) else { return day.date }
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.timeZone = utc
        formatter.setLocalizedDateFormatFromTemplate("EEE")
        return formatter.string(from: date)
    }

    private static let utc = TimeZone(identifier: "UTC")!

    /// A wall-clock `yyyy-MM-ddTHH:mm` read as UTC, so formatting it in UTC gives back the same hour.
    static func hourDate(_ text: String) -> Date? { parse(text, format: "yyyy-MM-dd'T'HH:mm") }

    static func dayDate(_ text: String) -> Date? { parse(text, format: "yyyy-MM-dd") }

    private static func parse(_ text: String, format: String) -> Date? {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = utc
        formatter.dateFormat = format
        return formatter.date(from: text)
    }

    private static func plausible(_ celsius: Double) -> Double? {
        celsius.isFinite && plausibleCelsius.contains(celsius) ? celsius : nil
    }

    private static func knownSymbol(_ name: String?) -> String? {
        name.flatMap(ExtensionItemSymbol.init(rawValue:))?.rawValue
    }

    private static func line(_ text: String, limit: Int) -> String {
        String(text.split(whereSeparator: \.isNewline).joined(separator: " ").trimmingCharacters(in: .whitespaces).prefix(limit))
    }
}
