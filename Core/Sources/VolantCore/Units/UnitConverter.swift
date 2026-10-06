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
    /// The speed of light reads alone ("speed of light") or as "c" when the other side is a speed,
    /// so "c in mph" converts while "c" beside a temperature stays Celsius. A bare number converts
    /// to counts ("30 in dozens").
    public static func convert(_ text: String, locale: Locale = .current) -> Conversion? {
        var lowered = text.lowercased().trimmingCharacters(in: .whitespaces)
        if lightNames.contains(lowered.filter { !$0.isWhitespace }) { lowered += " in m/s" }
        guard let (value, initialFrom, initialTo) = split(lowered, locale: locale) else { return nil }
        var from = initialFrom, to = initialTo
        if from.unit == UnitTemperature.celsius, to.unit is UnitSpeed { from = light }
        if to.unit == UnitTemperature.celsius, from.unit is UnitSpeed { to = light }
        guard let family = family(of: from.unit), family == self.family(of: to.unit) else { return nil }
        let result: Double
        if let fromFactor = factor(from.unit), let toFactor = factor(to.unit) {
            result = value * fromFactor / toFactor
        } else {
            result = Measurement(value: value, unit: from.unit).converted(to: to.unit).value
        }
        return Conversion(value: value, fromSymbol: from.symbol, result: result, toSymbol: to.symbol, fromUnit: from.unit, toUnit: to.unit)
    }

    private static let families: [Dimension.Type] = [
        UnitLength.self, UnitMass.self, UnitTemperature.self, UnitVolume.self, UnitSpeed.self, UnitDuration.self,
        UnitArea.self, UnitInformationStorage.self, UnitEnergy.self, UnitPower.self, UnitPressure.self, UnitCount.self
    ]

    /// The dimension a unit measures. Foundation's own units are instances of private subclasses,
    /// so a unit made here and a built-in one of the same dimension differ in their exact class.
    private static func family(of unit: Dimension) -> Int? {
        families.firstIndex { unit.isKind(of: $0) }
    }

    /// Names for the units Foundation lacks, which `MeasurementFormatter` cannot spell out.
    public static func name(of unit: Dimension) -> String? {
        customNames.first(where: { $0.0 == unit })?.1
    }

    public static func format(_ c: Conversion, locale: Locale = .current) -> String {
        "\(formatSource(c, locale: locale)) = \(formatResult(c, locale: locale))"
    }

    /// The input side as the card shows it; a bare count has no symbol ("30").
    public static func formatSource(_ c: Conversion, locale: Locale = .current) -> String {
        c.fromSymbol.isEmpty ? Calculator.format(c.value, locale: locale) : "\(Calculator.format(c.value, locale: locale)) \(c.fromSymbol)"
    }

    /// The converted side alone, rounded to six decimal places, as Copy puts it on the clipboard.
    public static func formatResult(_ c: Conversion, locale: Locale = .current) -> String {
        let number = Calculator.format((c.result * 1e6).rounded() / 1e6, locale: locale)
        return c.toSymbol.isEmpty ? number : "\(number) \(c.toSymbol)"
    }

    /// The same conversion the other way, for Swap; a bare count swaps back as "each".
    public static func swapQuery(_ c: Conversion, locale: Locale = .current) -> String {
        "\(formatResult(c, locale: locale)) in \(c.fromSymbol.isEmpty ? "each" : c.fromSymbol)"
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
        (UnitPressure.poundsForcePerSquareInch, 6894.757293168361), (UnitPressure.millimetersOfMercury, 133.322387415),
        (UnitLength.lightyears, 9_460_730_472_580_800), (UnitLength.astronomicalUnits, 149_597_870_700),
        (UnitLength.parsecs, 149_597_870_700 * 648_000 / Double.pi)
    ]

    /// Units Foundation lacks, at their defined sizes: the standard atmosphere and the torr
    /// (1/760 atm), the International Table BTU, Mach 1 as the speed of sound in the ISA sea-level
    /// atmosphere at 15 °C (an assumption, since Mach depends on temperature), the speed of light,
    /// and counts.
    private static let atmosphere = UnitPressure(symbol: "atm", converter: UnitConverterLinear(coefficient: 101_325))
    private static let torr = UnitPressure(symbol: "Torr", converter: UnitConverterLinear(coefficient: 101_325.0 / 760))
    private static let btu = UnitEnergy(symbol: "BTU", converter: UnitConverterLinear(coefficient: 1055.05585262))
    private static let mach = UnitSpeed(symbol: "Mach", converter: UnitConverterLinear(coefficient: 340.29))
    private static let light = Spec(unit: UnitSpeed(symbol: "c", converter: UnitConverterLinear(coefficient: 299_792_458)), symbol: "c")
    private static let lightNames: Set<String> = ["speedoflight", "lightspeed", "thespeedoflight"]

    private static let customNames: [(Dimension, String)] = [
        (atmosphere, "Standard atmospheres"), (torr, "Torr"), (btu, "British thermal units (IT)"),
        (mach, "Mach (sea level, 15 °C)"), (light.unit, "Speed of light"),
        (UnitCount.dozen, "Dozen"), (UnitCount.gross, "Gross"), (UnitPressure.newtonsPerMetersSquared, "Pascals")
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
                if let constant = constant(String(lhs), to: to, locale: locale) { return (constant.0, constant.1, to) }
                let negative = lhs.first == "-"
                guard let (magnitude, end) = NumberLiteral.scan(lhs, from: negative ? 1 : 0, separators, magnitudes: false) else { continue }
                let rest = String(lhs[end...])
                if rest.allSatisfy(\.isWhitespace), to.unit is UnitCount { return (negative ? -magnitude : magnitude, each, to) }
                guard let from = lookup(rest) else { continue }
                return (negative ? -magnitude : magnitude, from, to)
            }
        }
        return nil
    }

    private static let each = Spec(unit: UnitCount.each, symbol: "")

    /// A source written without a leading number: the speed of light ("c", "speed of light"),
    /// counted once, and "mach 2", which puts the number after the unit as pilots say it.
    private static func constant(_ lhs: String, to: Spec, locale: Locale) -> (Double, Spec)? {
        let key = lhs.filter { !$0.isWhitespace }
        if to.unit is UnitSpeed, key == "c" || lightNames.contains(key) { return (1, light) }
        guard key.hasPrefix("mach") else { return nil }
        let number = Array(key.dropFirst(4))
        if number.isEmpty { return (1, Spec(unit: mach, symbol: "Mach")) }
        guard let (value, end) = NumberLiteral.scan(number, from: 0, NumberLiteral.Separators(locale), magnitudes: false),
              end == number.count else { return nil }
        return (value, Spec(unit: mach, symbol: "Mach"))
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
        add(["hpa", "hectopascal", "hectopascals"], UnitPressure.hectopascals, "hPa")
        add(["mbar", "millibar", "millibars"], UnitPressure.millibars, "mbar")
        add(["atm", "atmosphere", "atmospheres"], atmosphere, "atm")
        add(["torr"], torr, "Torr")
        add(["btu", "btus"], btu, "BTU")
        add(["mach"], mach, "Mach")
        add(["ly", "lightyear", "lightyears", "light-year", "light-years"], UnitLength.lightyears, "ly")
        add(["au", "astronomicalunit", "astronomicalunits"], UnitLength.astronomicalUnits, "au")
        add(["pc", "parsec", "parsecs"], UnitLength.parsecs, "pc")
        add(["each", "pcs", "pieces", "items"], UnitCount.each, "")
        add(["dozen", "dozens", "doz"], UnitCount.dozen, "dozen")
        add(["gross"], UnitCount.gross, "gross")
        return t
    }()
}

/// Counts of things, so "30 in dozens" converts; "each" is one item.
final class UnitCount: Dimension, @unchecked Sendable {
    static let each = UnitCount(symbol: "each", converter: UnitConverterLinear(coefficient: 1))
    static let dozen = UnitCount(symbol: "dozen", converter: UnitConverterLinear(coefficient: 12))
    static let gross = UnitCount(symbol: "gross", converter: UnitConverterLinear(coefficient: 144))

    override class func baseUnit() -> UnitCount { each }
}
