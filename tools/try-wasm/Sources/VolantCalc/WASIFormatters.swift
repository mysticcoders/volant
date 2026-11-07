import Foundation

// swift-corelibs-foundation marks MeasurementFormatter and DateComponentsFormatter unavailable on
// WASI. These module-local stand-ins shadow them for the calculator's few uses, in English only:
// "3 days" style counts, and long unit names from a small table that falls back to the unit symbol.

/// The `.full` units style the calculator asks for.
enum WASIUnitsStyle { case full }

/// English counts of one calendar or clock unit, as `DateComponentsFormatter` writes them with
/// `unitsStyle = .full` and `maximumUnitCount = 1`.
final class DateComponentsFormatter {
    var calendar: Calendar?
    var unitsStyle: WASIUnitsStyle = .full
    var maximumUnitCount = 0
    var allowedUnits: NSCalendar.Unit = []

    /// "1 day", "1,992 hours": the first allowed unit's value with an English singular or plural.
    func string(from components: DateComponents) -> String? {
        let pairs: [(NSCalendar.Unit, Int?, String)] = [
            (.year, components.year, "year"), (.weekOfMonth, components.weekOfMonth, "week"),
            (.day, components.day, "day"), (.hour, components.hour, "hour"),
            (.minute, components.minute, "minute"), (.second, components.second, "second"),
        ]
        guard let (_, value, word) = pairs.first(where: { allowedUnits.contains($0.0) && $0.1 != nil }), let value else { return nil }
        let number = NumberFormatter()
        number.numberStyle = .decimal
        number.locale = Locale(identifier: "en_US")
        let text = number.string(from: NSNumber(value: value)) ?? String(value)
        return "\(text) \(word)\(abs(value) == 1 ? "" : "s")"
    }
}

/// The `.long` unit style and `.providedUnit` options the calculator sets.
enum WASIUnitStyle { case long }
struct WASIUnitOptions: OptionSet { let rawValue: Int; static let providedUnit = WASIUnitOptions(rawValue: 1) }

/// English long unit names, and measurements written as "3.25 hours".
final class MeasurementFormatter {
    var locale: Locale = Locale(identifier: "en_US")
    var unitStyle: WASIUnitStyle = .long
    var unitOptions: WASIUnitOptions = []
    var numberFormatter: NumberFormatter?

    /// Plural English names by unit symbol; anything else reads as its symbol.
    private static let names: [String: String] = [
        "km": "kilometers", "m": "meters", "cm": "centimeters", "mm": "millimeters", "mi": "miles",
        "yd": "yards", "ft": "feet", "in": "inches", "nmi": "nautical miles", "kg": "kilograms", "g": "grams",
        "mg": "milligrams", "lb": "pounds", "oz": "ounces", "st": "stones", "t": "metric tons",
        "L": "liters", "mL": "milliliters", "gal": "gallons", "qt": "quarts", "pt": "pints", "cup": "cups",
        "fl oz": "fluid ounces", "tbsp": "tablespoons", "tsp": "teaspoons", "°C": "degrees Celsius",
        "°F": "degrees Fahrenheit", "K": "kelvins", "km/h": "kilometers per hour", "mph": "miles per hour",
        "m/s": "meters per second", "kn": "knots", "s": "seconds", "min": "minutes", "hr": "hours",
        "m²": "square meters", "km²": "square kilometers", "ft²": "square feet", "ac": "acres", "ha": "hectares",
        "B": "bytes", "kB": "kilobytes", "MB": "megabytes", "GB": "gigabytes", "TB": "terabytes",
    ]

    /// The unit's long English name, or its symbol when the table has none.
    func string(from unit: Unit) -> String { Self.names[unit.symbol] ?? unit.symbol }

    /// A value with the unit's long name: "3.25 hours".
    func string<U: Unit>(from measurement: Measurement<U>) -> String {
        let number = numberFormatter?.string(from: NSNumber(value: measurement.value)) ?? String(measurement.value)
        return "\(number) \(string(from: measurement.unit))"
    }
}
