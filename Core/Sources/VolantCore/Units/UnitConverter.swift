import Foundation

/// Offline unit conversion on Foundation's Measurement types. Parses "5 km in mi", "72f to c", "3.5 gb as mb".
public enum UnitConverter {
    public struct Conversion: Equatable {
        public let value: Double
        public let fromSymbol: String
        public let result: Double
        public let toSymbol: String

        public init(value: Double, fromSymbol: String, result: Double, toSymbol: String) {
            self.value = value
            self.fromSymbol = fromSymbol
            self.result = result
            self.toSymbol = toSymbol
        }
    }

    private struct Spec {
        let unit: Dimension
        let symbol: String
    }

    public static func convert(_ text: String) -> Conversion? {
        let lowered = text.lowercased().trimmingCharacters(in: .whitespaces)
        guard let (value, fromText, toText) = split(lowered),
              let from = lookup(fromText), let to = lookup(toText),
              type(of: from.unit) == type(of: to.unit) else { return nil }
        let measurement = Measurement(value: value, unit: from.unit)
        let converted = measurement.converted(to: to.unit)
        return Conversion(value: value, fromSymbol: from.symbol, result: converted.value, toSymbol: to.symbol)
    }

    public static func format(_ c: Conversion) -> String {
        "\(Calculator.format(c.value)) \(c.fromSymbol) = \(Calculator.format((c.result * 1e6).rounded() / 1e6)) \(c.toSymbol)"
    }

    /// Splits "<number><unit> (in|to|as|=) <unit>" allowing the number and unit to touch, as in "72f".
    private static func split(_ text: String) -> (Double, String, String)? {
        let separators = [" in ", " to ", " as ", " = ", "="]
        var parts: [String]? = nil
        for sep in separators where text.contains(sep) {
            let p = text.components(separatedBy: sep)
            if p.count == 2 { parts = p.map { $0.trimmingCharacters(in: .whitespaces) }; break }
        }
        guard let parts, let toText = parts.last, !toText.isEmpty else { return nil }
        let lhs = parts[0]
        let scalars = Array(lhs)
        var i = 0
        while i < scalars.count, scalars[i].isNumber || scalars[i] == "." || (i == 0 && scalars[i] == "-") { i += 1 }
        guard i > 0, let value = Double(String(scalars[0..<i])) else { return nil }
        let fromText = String(scalars[i...]).trimmingCharacters(in: .whitespaces)
        guard !fromText.isEmpty else { return nil }
        return (value, fromText, toText)
    }

    private static func lookup(_ raw: String) -> Spec? {
        let key = raw.replacingOccurrences(of: "°", with: "").trimmingCharacters(in: .whitespaces)
        return table[key]
    }

    private static let table: [String: Spec] = {
        var t: [String: Spec] = [:]
        func add(_ names: [String], _ unit: Dimension, _ symbol: String) { for n in names { t[n] = Spec(unit: unit, symbol: symbol) } }
        add(["m", "meter", "meters", "metre", "metres"], UnitLength.meters, "m")
        add(["km", "kilometer", "kilometers", "kilometre", "kilometres"], UnitLength.kilometers, "km")
        add(["cm", "centimeter", "centimeters"], UnitLength.centimeters, "cm")
        add(["mm", "millimeter", "millimeters"], UnitLength.millimeters, "mm")
        add(["mi", "mile", "miles"], UnitLength.miles, "mi")
        add(["ft", "foot", "feet"], UnitLength.feet, "ft")
        add(["in", "inch", "inches"], UnitLength.inches, "in")
        add(["yd", "yard", "yards"], UnitLength.yards, "yd")
        add(["nmi", "nm", "nautical", "nauticalmile", "nauticalmiles"], UnitLength.nauticalMiles, "nmi")
        add(["kg", "kilogram", "kilograms"], UnitMass.kilograms, "kg")
        add(["g", "gram", "grams"], UnitMass.grams, "g")
        add(["mg", "milligram", "milligrams"], UnitMass.milligrams, "mg")
        add(["lb", "lbs", "pound", "pounds"], UnitMass.pounds, "lb")
        add(["oz", "ounce", "ounces"], UnitMass.ounces, "oz")
        add(["st", "stone", "stones"], UnitMass.stones, "st")
        add(["c", "celsius", "centigrade"], UnitTemperature.celsius, "°C")
        add(["f", "fahrenheit"], UnitTemperature.fahrenheit, "°F")
        add(["k", "kelvin"], UnitTemperature.kelvin, "K")
        add(["l", "liter", "liters", "litre", "litres"], UnitVolume.liters, "L")
        add(["ml", "milliliter", "milliliters"], UnitVolume.milliliters, "mL")
        add(["gal", "gallon", "gallons"], UnitVolume.gallons, "gal")
        add(["qt", "quart", "quarts"], UnitVolume.quarts, "qt")
        add(["pt", "pint", "pints"], UnitVolume.pints, "pt")
        add(["cup", "cups"], UnitVolume.cups, "cup")
        add(["floz", "fluidounce", "fluidounces"], UnitVolume.fluidOunces, "fl oz")
        add(["tbsp", "tablespoon", "tablespoons"], UnitVolume.tablespoons, "tbsp")
        add(["tsp", "teaspoon", "teaspoons"], UnitVolume.teaspoons, "tsp")
        add(["kph", "kmh", "km/h", "kmph"], UnitSpeed.kilometersPerHour, "km/h")
        add(["mph", "mi/h"], UnitSpeed.milesPerHour, "mph")
        add(["m/s", "mps"], UnitSpeed.metersPerSecond, "m/s")
        add(["kn", "kt", "kts", "knot", "knots"], UnitSpeed.knots, "kn")
        add(["s", "sec", "secs", "second", "seconds"], UnitDuration.seconds, "s")
        add(["min", "mins", "minute", "minutes"], UnitDuration.minutes, "min")
        add(["h", "hr", "hrs", "hour", "hours"], UnitDuration.hours, "h")
        add(["m2", "sqm", "squaremeters"], UnitArea.squareMeters, "m²")
        add(["km2", "sqkm"], UnitArea.squareKilometers, "km²")
        add(["ft2", "sqft", "squarefeet"], UnitArea.squareFeet, "ft²")
        add(["acre", "acres", "ac"], UnitArea.acres, "acre")
        add(["ha", "hectare", "hectares"], UnitArea.hectares, "ha")
        add(["b", "byte", "bytes"], UnitInformationStorage.bytes, "B")
        add(["kb", "kilobyte", "kilobytes"], UnitInformationStorage.kilobytes, "kB")
        add(["mb", "megabyte", "megabytes"], UnitInformationStorage.megabytes, "MB")
        add(["gb", "gigabyte", "gigabytes"], UnitInformationStorage.gigabytes, "GB")
        add(["tb", "terabyte", "terabytes"], UnitInformationStorage.terabytes, "TB")
        add(["kib"], UnitInformationStorage.kibibytes, "KiB")
        add(["mib"], UnitInformationStorage.mebibytes, "MiB")
        add(["gib"], UnitInformationStorage.gibibytes, "GiB")
        add(["j", "joule", "joules"], UnitEnergy.joules, "J")
        add(["kj", "kilojoule", "kilojoules"], UnitEnergy.kilojoules, "kJ")
        add(["cal", "calorie", "calories"], UnitEnergy.calories, "cal")
        add(["kcal", "kilocalorie", "kilocalories"], UnitEnergy.kilocalories, "kcal")
        add(["kwh", "kilowatthour", "kilowatthours"], UnitEnergy.kilowattHours, "kWh")
        add(["w", "watt", "watts"], UnitPower.watts, "W")
        add(["kw", "kilowatt", "kilowatts"], UnitPower.kilowatts, "kW")
        add(["hp", "horsepower"], UnitPower.horsepower, "hp")
        add(["pa", "pascal", "pascals"], UnitPressure.newtonsPerMetersSquared, "Pa")
        add(["kpa", "kilopascal", "kilopascals"], UnitPressure.kilopascals, "kPa")
        add(["bar", "bars"], UnitPressure.bars, "bar")
        add(["psi"], UnitPressure.poundsForcePerSquareInch, "psi")
        add(["mmhg"], UnitPressure.millimetersOfMercury, "mmHg")
        return t
    }()
}
