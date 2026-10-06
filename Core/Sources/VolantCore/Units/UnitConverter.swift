import Foundation

/// Offline unit conversion on Foundation's Measurement types. Parses "5 km in mi", "72f to c", "3.5 gb as mb".
public enum UnitConverter {
    public struct Conversion: Equatable {
        public let value: Double
        public let fromSymbol: String
        public let result: Double
        public let toSymbol: String
        public let fromUnit: Dimension?
        public let toUnit: Dimension?

        public init(value: Double, fromSymbol: String, result: Double, toSymbol: String, fromUnit: Dimension? = nil, toUnit: Dimension? = nil) {
            self.value = value
            self.fromSymbol = fromSymbol
            self.result = result
            self.toSymbol = toSymbol
            self.fromUnit = fromUnit
            self.toUnit = toUnit
        }
    }

    private struct Spec {
        let unit: Dimension
        let symbol: String
    }

    /// Numbers follow `locale` (see `NumberLiteral`), without magnitude suffixes, since "100k" here is kelvin.
    public static func convert(_ text: String, locale: Locale = .current) -> Conversion? {
        let lowered = text.lowercased().trimmingCharacters(in: .whitespaces)
        guard let (value, from, to) = split(lowered, locale: locale), type(of: from.unit) == type(of: to.unit) else { return nil }
        let result: Double
        if let fromFactor = factor(from.unit), let toFactor = factor(to.unit) {
            result = value * fromFactor / toFactor
        } else {
            result = Measurement(value: value, unit: from.unit).converted(to: to.unit).value
        }
        return Conversion(value: value, fromSymbol: from.symbol, result: result, toSymbol: to.symbol, fromUnit: from.unit, toUnit: to.unit)
    }

    public static func format(_ c: Conversion, locale: Locale = .current) -> String {
        "\(Calculator.format(c.value, locale: locale)) \(c.fromSymbol) = \(formatResult(c, locale: locale))"
    }

    /// The converted side alone, rounded to six decimal places, as Copy puts it on the clipboard.
    public static func formatResult(_ c: Conversion, locale: Locale = .current) -> String {
        "\(Calculator.format((c.result * 1e6).rounded() / 1e6, locale: locale)) \(c.toSymbol)"
    }

    /// Exact legal definitions where Foundation's coefficients are rounded to about six digits,
    /// which showed in answers ("10 kn in kph" gave 18.519969). Cup is the US customary cup
    /// (236.588 mL); Foundation's 0.24 L is the US nutrition-label cup.
    private static let exactFactors: [(Dimension, Double)] = [
        (UnitMass.pounds, 0.45359237), (UnitMass.ounces, 0.028349523125), (UnitMass.stones, 6.35029318),
        (UnitVolume.gallons, 3.785411784), (UnitVolume.quarts, 0.946352946), (UnitVolume.pints, 0.473176473),
        (UnitVolume.cups, 0.2365882365), (UnitVolume.fluidOunces, 0.0295735295625),
        (UnitVolume.tablespoons, 0.01478676478125), (UnitVolume.teaspoons, 0.00492892159375),
        (UnitSpeed.kilometersPerHour, 1 / 3.6), (UnitSpeed.knots, 1852.0 / 3600),
        (UnitPower.horsepower, 745.69987158227022),
        (UnitPressure.poundsForcePerSquareInch, 6894.757293168361), (UnitPressure.millimetersOfMercury, 133.322387415)
    ]

    /// A linear unit's size in its dimension's base unit; nil for offset scales such as
    /// temperature, which convert through Foundation.
    private static func factor(_ unit: Dimension) -> Double? {
        if let exact = exactFactors.first(where: { $0.0 == unit })?.1 { return exact }
        guard let linear = unit.converter as? UnitConverterLinear, linear.constant == 0 else { return nil }
        return linear.coefficient
    }

    /// Splits "<number><unit> (in|to|as|=) <unit>", allowing the number and unit to touch ("72f").
    /// Every separator position is tried, so "5 in in cm" reads inches even though "in" also
    /// introduces the target.
    private static func split(_ text: String, locale: Locale) -> (Double, Spec, Spec)? {
        let separators = NumberLiteral.Separators(locale)
        for separator in [" in ", " to ", " as ", " = ", "="] {
            var search = text.startIndex
            while let range = text.range(of: separator, range: search..<text.endIndex) {
                search = range.lowerBound < text.endIndex ? text.index(after: range.lowerBound) : text.endIndex
                let lhs = Array(text[..<range.lowerBound].trimmingCharacters(in: .whitespaces))
                guard let to = lookup(String(text[range.upperBound...])) else { continue }
                let negative = lhs.first == "-"
                guard let (magnitude, end) = NumberLiteral.scan(lhs, from: negative ? 1 : 0, separators, magnitudes: false),
                      let from = lookup(String(lhs[end...])) else { continue }
                return (negative ? -magnitude : magnitude, from, to)
            }
        }
        return nil
    }

    /// Unit names ignore spacing and the degree sign, and read superscript squares, so the
    /// converter's own symbols ("ft²", "°F") work as input: "sq ft", "fl oz", "square feet".
    private static func lookup(_ raw: String) -> Spec? {
        let key = raw.replacingOccurrences(of: "°", with: "").replacingOccurrences(of: "²", with: "2").filter { !$0.isWhitespace }
        return key.isEmpty ? nil : table[key]
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
        add(["m2", "sqm", "squaremeter", "squaremeters", "squaremetre", "squaremetres"], UnitArea.squareMeters, "m²")
        add(["km2", "sqkm"], UnitArea.squareKilometers, "km²")
        add(["ft2", "sqft", "squarefoot", "squarefeet"], UnitArea.squareFeet, "ft²")
        add(["mi2", "sqmi", "squaremile", "squaremiles"], UnitArea.squareMiles, "mi²")
        add(["yd2", "sqyd", "squareyard", "squareyards"], UnitArea.squareYards, "yd²")
        add(["in2", "sqin", "squareinch", "squareinches"], UnitArea.squareInches, "in²")
        add(["cm2", "sqcm", "squarecentimeter", "squarecentimeters"], UnitArea.squareCentimeters, "cm²")
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
