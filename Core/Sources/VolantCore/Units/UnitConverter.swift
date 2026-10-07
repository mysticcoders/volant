import Foundation

/// Offline unit conversion on Foundation's Measurement types. Parses "5 km in mi", "72f to c", "3.5 gb as mb".
///
/// Beyond Foundation's units: days, weeks and years (a year is the average Gregorian year of
/// 365.2425 days), data rates ("100 Mbps in MB/s"), fuel economy ("30 mpg in l/100km", US gallons
/// unless "mpg imp"), and running pace ("8 min/mile in kph"). Fuel economy and pace are reciprocal
/// to their counterparts, so they convert through `Reciprocal` rather than a factor. Feet and inches
/// may be written with primes: "6' in cm", "5'10\" in cm".
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

    struct Spec {
        let unit: Dimension
        let symbol: String
    }

    /// Numbers follow `locale` (see `NumberLiteral`), without magnitude suffixes, since "100k" here is kelvin.
    /// The speed of light reads alone ("speed of light") or as "c" when the other side is a speed,
    /// so "c in mph" converts while "c" beside a temperature stays Celsius. A bare number converts
    /// to counts ("30 in dozens"). A temperature with no target converts to the other common scale:
    /// "98.6 f" gives °C and "37 c" gives °F.
    public static func convert(_ text: String, locale: Locale = .current) -> Conversion? {
        var lowered = normalized(text)
        if lightNames.contains(lowered.filter { !$0.isWhitespace }) { lowered += " in m/s" }
        if let scale = bareTemperature(lowered) { lowered += scale == "c" ? " in f" : " in c" }
        guard let (value, initialFrom, initialTo) = split(lowered, locale: locale) else { return nil }
        var from = initialFrom, to = initialTo
        if from.unit == UnitTemperature.celsius, to.unit is UnitSpeed { from = light }
        if to.unit == UnitTemperature.celsius, from.unit is UnitSpeed { to = light }
        guard sameDimension(from.unit, to.unit) else { return nil }
        let result = convert(value, from: from.unit, to: to.unit)
        guard result.isFinite else { return nil }
        return Conversion(value: value, fromSymbol: from.symbol, result: result, toSymbol: to.symbol, fromUnit: from.unit, toUnit: to.unit)
    }

    private static let families: [Dimension.Type] = [
        UnitLength.self, UnitMass.self, UnitTemperature.self, UnitVolume.self, UnitSpeed.self, UnitDuration.self,
        UnitArea.self, UnitInformationStorage.self, UnitEnergy.self, UnitPower.self, UnitPressure.self, UnitCount.self,
        UnitDataRate.self, UnitFuelEfficiency.self
    ]

    /// The dimension a unit measures. Foundation's own units are instances of private subclasses,
    /// so a unit made here and a built-in one of the same dimension differ in their exact class.
    private static func family(of unit: Dimension) -> Int? {
        families.firstIndex { unit.isKind(of: $0) }
    }

    /// Whether two units measure the same thing.
    static func sameDimension(_ a: Dimension, _ b: Dimension) -> Bool {
        guard let family = family(of: a) else { return false }
        return family == self.family(of: b)
    }

    /// Names for the units Foundation lacks, which `MeasurementFormatter` cannot spell out.
    public static func name(of unit: Dimension) -> String? {
        customNames.first(where: { $0.0 == unit })?.1 ?? Extra.names[ObjectIdentifier(unit)]
    }

    /// A value in one unit expressed in another of the same dimension, through the base unit. Linear
    /// sides use the exact factors; offset and reciprocal sides use their own converters.
    static func convert(_ value: Double, from: Dimension, to: Dimension) -> Double {
        let base = factor(from).map { value * $0 } ?? from.converter.baseUnitValue(fromValue: value)
        return factor(to).map { base / $0 } ?? to.converter.value(fromBaseUnitValue: base)
    }

    /// Lowercases the query after the steps that need its case or punctuation: data rates, where
    /// "Mb/s" and "Mbps" are bits and "MB/s" bytes (all-lowercase "mb/s" stays bytes, like "mb"),
    /// become "mbit/s" or "mbyte/s"; primes become feet and inches, so "5'10\"" reads "5 ft 10 in".
    static func normalized(_ text: String) -> String {
        var value = text.trimmingCharacters(in: .whitespaces)
        let range = NSRange(value.startIndex..., in: value)
        for match in rate.matches(in: value, range: range).reversed() {
            guard let whole = Range(match.range, in: value), let prefixRange = Range(match.range(at: 1), in: value),
                  let letterRange = Range(match.range(at: 2), in: value), let tailRange = Range(match.range(at: 3), in: value) else { continue }
            let prefix = String(value[prefixRange]), letter = value[letterRange], tail = value[tailRange].lowercased()
            let bits: Bool
            switch tail {
            case "it/s", "its/s", "itps": bits = true
            case "yte/s", "ytes/s": bits = false
            case "ps": bits = letter == "b"
            default: bits = letter == "b" && prefix.contains(where: \.isUppercase)
            }
            value.replaceSubrange(whole, with: prefix.lowercased() + (bits ? "bit/s" : "byte/s"))
        }
        value = value.replacingOccurrences(of: #"(\d)\s*['’′]\s*(\d+(?:\.\d+)?)\s*(?:["”″]|'')"#, with: "$1 ft $2 in", options: .regularExpression)
        value = value.replacingOccurrences(of: #"(\d)\s*(?:["”″]|'')"#, with: "$1 in", options: .regularExpression)
        value = value.replacingOccurrences(of: #"(\d)\s*['’′](?!\w)"#, with: "$1 ft", options: .regularExpression)
        return value.lowercased()
    }

    private static let rate = try! NSRegularExpression(pattern: #"(?<![A-Za-z])([kKmMgGtT]?i?)([bB])(it/s|its/s|itps|yte/s|ytes/s|ps|/s)(?![A-Za-z])"#)

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
    /// atmosphere at 15 °C (an assumption, since Mach depends on temperature), the 250 mL metric
    /// cup, the speed of light, and counts.
    private static let atmosphere = UnitPressure(symbol: "atm", converter: UnitConverterLinear(coefficient: 101_325))
    private static let torr = UnitPressure(symbol: "Torr", converter: UnitConverterLinear(coefficient: 101_325.0 / 760))
    private static let btu = UnitEnergy(symbol: "BTU", converter: UnitConverterLinear(coefficient: 1055.05585262))
    private static let metricCup = UnitVolume(symbol: "metric cup", converter: UnitConverterLinear(coefficient: 0.25))
    private static let mach = UnitSpeed(symbol: "Mach", converter: UnitConverterLinear(coefficient: 340.29))
    private static let light = Spec(unit: UnitSpeed(symbol: "c", converter: UnitConverterLinear(coefficient: 299_792_458)), symbol: "c")
    private static let lightNames: Set<String> = ["speedoflight", "lightspeed", "thespeedoflight"]

    private static let customNames: [(Dimension, String)] = [
        (atmosphere, "Standard atmospheres"), (torr, "Torr"), (btu, "British thermal units (IT)"),
        (mach, "Mach (sea level, 15 °C)"), (metricCup, "Metric cups"), (light.unit, "Speed of light"),
        (UnitCount.dozen, "Dozen"), (UnitCount.gross, "Gross"), (UnitPressure.newtonsPerMetersSquared, "Pascals")
    ]

    /// A linear unit's size in its dimension's base unit; nil for offset scales such as
    /// temperature, which convert through Foundation.
    static func factor(_ unit: Dimension) -> Double? {
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
    private static let temperatureAlone = try! NSRegularExpression(pattern:
        #"^-?\d[\d.,]*\s*(?:°\s*|degrees?\s+)?(c|f|celsius|centigrade|fahrenheit)$"#)

    /// "c" or "f" when the whole query is a number and a Celsius or Fahrenheit mark, such as
    /// "98.6 f", "37°C" or "20 degrees celsius"; a number alone or with a bare degree sign stays
    /// unconverted, since the scale is unknown.
    private static func bareTemperature(_ text: String) -> String? {
        guard text.utf8.count <= 32, let match = temperatureAlone.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let scale = Range(match.range(at: 1), in: text) else { return nil }
        return text[scale].first == "f" ? "f" : "c"
    }

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
    static func lookup(_ raw: String) -> Spec? {
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
        add(["c", "celsius", "centigrade", "degreesc", "degreec", "degreescelsius", "degreecelsius"], UnitTemperature.celsius, "°C")
        add(["f", "fahrenheit", "degreesf", "degreef", "degreesfahrenheit", "degreefahrenheit"], UnitTemperature.fahrenheit, "°F")
        add(["k", "kelvin"], UnitTemperature.kelvin, "K")
        add(["l", "liter", "liters", "litre", "litres"], UnitVolume.liters, "L")
        add(["ml", "milliliter", "milliliters"], UnitVolume.milliliters, "mL")
        add(["gal", "gallon", "gallons"], UnitVolume.gallons, "gal")
        add(["qt", "quart", "quarts"], UnitVolume.quarts, "qt")
        add(["pt", "pint", "pints"], UnitVolume.pints, "pt")
        add(["cup", "cups"], UnitVolume.cups, "cup")
        add(["metriccup", "metriccups"], metricCup, "metric cup")
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
        add(["d", "day", "days"], Extra.days, "d")
        add(["wk", "wks", "week", "weeks"], Extra.weeks, "wk")
        add(["yr", "yrs", "year", "years"], Extra.years, "yr")
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
        add(["bit/s"], Extra.bitsPerSecond, "bps")
        add(["kbit/s"], Extra.kilobitsPerSecond, "kbps")
        add(["mbit/s"], Extra.megabitsPerSecond, "Mbps")
        add(["gbit/s"], Extra.gigabitsPerSecond, "Gbps")
        add(["tbit/s"], Extra.terabitsPerSecond, "Tbps")
        add(["byte/s"], Extra.bytesPerSecond, "B/s")
        add(["kbyte/s"], Extra.kilobytesPerSecond, "kB/s")
        add(["mbyte/s"], Extra.megabytesPerSecond, "MB/s")
        add(["gbyte/s"], Extra.gigabytesPerSecond, "GB/s")
        add(["tbyte/s"], Extra.terabytesPerSecond, "TB/s")
        add(["kibyte/s"], Extra.kibibytesPerSecond, "KiB/s")
        add(["mibyte/s"], Extra.mebibytesPerSecond, "MiB/s")
        add(["gibyte/s"], Extra.gibibytesPerSecond, "GiB/s")
        add(["mpg", "mpgus", "mpg(us)", "milespergallon"], Extra.milesPerGallon, "mpg")
        add(["mpgimp", "mpguk", "mpg(imp)", "mpg(uk)", "imperialmpg"], Extra.milesPerImperialGallon, "mpg (imp)")
        add(["l/100km", "liters/100km", "litres/100km", "lper100km"], UnitFuelEfficiency.litersPer100Kilometers, "L/100 km")
        add(["km/l", "kmpl", "kpl"], Extra.kilometersPerLiter, "km/L")
        add(["min/mi", "min/mile", "minpermile", "minutespermile", "minutepermile"], Extra.minutesPerMile, "min/mi")
        add(["min/km", "minperkm", "minutesperkm", "minuteperkm", "minperkilometer", "minutesperkilometer"],
            Extra.minutesPerKilometer, "min/km")
        return t
    }()

    /// Units beyond Foundation's: calendar durations, data rates, and the reciprocal fuel
    /// economy and pace units.
    enum Extra {
        static let days = UnitDuration(symbol: "d", converter: UnitConverterLinear(coefficient: 86_400))
        static let weeks = UnitDuration(symbol: "wk", converter: UnitConverterLinear(coefficient: 604_800))
        static let years = UnitDuration(symbol: "yr", converter: UnitConverterLinear(coefficient: 31_556_952))
        static let bitsPerSecond = UnitDataRate(symbol: "bps", converter: UnitConverterLinear(coefficient: 1))
        static let kilobitsPerSecond = UnitDataRate(symbol: "kbps", converter: UnitConverterLinear(coefficient: 1e3))
        static let megabitsPerSecond = UnitDataRate(symbol: "Mbps", converter: UnitConverterLinear(coefficient: 1e6))
        static let gigabitsPerSecond = UnitDataRate(symbol: "Gbps", converter: UnitConverterLinear(coefficient: 1e9))
        static let terabitsPerSecond = UnitDataRate(symbol: "Tbps", converter: UnitConverterLinear(coefficient: 1e12))
        static let bytesPerSecond = UnitDataRate(symbol: "B/s", converter: UnitConverterLinear(coefficient: 8))
        static let kilobytesPerSecond = UnitDataRate(symbol: "kB/s", converter: UnitConverterLinear(coefficient: 8e3))
        static let megabytesPerSecond = UnitDataRate(symbol: "MB/s", converter: UnitConverterLinear(coefficient: 8e6))
        static let gigabytesPerSecond = UnitDataRate(symbol: "GB/s", converter: UnitConverterLinear(coefficient: 8e9))
        static let terabytesPerSecond = UnitDataRate(symbol: "TB/s", converter: UnitConverterLinear(coefficient: 8e12))
        static let kibibytesPerSecond = UnitDataRate(symbol: "KiB/s", converter: UnitConverterLinear(coefficient: 8 * 1024))
        static let mebibytesPerSecond = UnitDataRate(symbol: "MiB/s", converter: UnitConverterLinear(coefficient: 8 * 1_048_576))
        static let gibibytesPerSecond = UnitDataRate(symbol: "GiB/s", converter: UnitConverterLinear(coefficient: 8 * 1_073_741_824))
        static let milesPerGallon = UnitFuelEfficiency(symbol: "mpg", converter: Reciprocal(100 * 3.785411784 / 1.609344))
        static let milesPerImperialGallon = UnitFuelEfficiency(symbol: "mpg (imp)", converter: Reciprocal(100 * 4.54609 / 1.609344))
        static let kilometersPerLiter = UnitFuelEfficiency(symbol: "km/L", converter: Reciprocal(100))
        static let minutesPerMile = UnitSpeed(symbol: "min/mi", converter: Reciprocal(1609.344 / 60))
        static let minutesPerKilometer = UnitSpeed(symbol: "min/km", converter: Reciprocal(1000.0 / 60))

        static let names: [ObjectIdentifier: String] = [
            ObjectIdentifier(days): "Days", ObjectIdentifier(weeks): "Weeks", ObjectIdentifier(years): "Years of 365.2425 days",
            ObjectIdentifier(bitsPerSecond): "Bits per second", ObjectIdentifier(kilobitsPerSecond): "Kilobits per second",
            ObjectIdentifier(megabitsPerSecond): "Megabits per second", ObjectIdentifier(gigabitsPerSecond): "Gigabits per second",
            ObjectIdentifier(terabitsPerSecond): "Terabits per second", ObjectIdentifier(bytesPerSecond): "Bytes per second",
            ObjectIdentifier(kilobytesPerSecond): "Kilobytes per second", ObjectIdentifier(megabytesPerSecond): "Megabytes per second",
            ObjectIdentifier(gigabytesPerSecond): "Gigabytes per second", ObjectIdentifier(terabytesPerSecond): "Terabytes per second",
            ObjectIdentifier(kibibytesPerSecond): "Kibibytes per second", ObjectIdentifier(mebibytesPerSecond): "Mebibytes per second",
            ObjectIdentifier(gibibytesPerSecond): "Gibibytes per second", ObjectIdentifier(milesPerGallon): "Miles per US gallon",
            ObjectIdentifier(milesPerImperialGallon): "Miles per imperial gallon", ObjectIdentifier(kilometersPerLiter): "Kilometers per liter",
            ObjectIdentifier(minutesPerMile): "Minutes per mile", ObjectIdentifier(minutesPerKilometer): "Minutes per kilometer"
        ]
    }

    /// A unit whose base value is a constant divided by its own, as miles per gallon is to liters
    /// per 100 km and pace is to speed. Zero maps to infinity, which callers reject.
    final class Reciprocal: Foundation.UnitConverter {
        let constant: Double

        init(_ constant: Double) {
            self.constant = constant
            super.init()
        }

        override func baseUnitValue(fromValue value: Double) -> Double { constant / value }

        override func value(fromBaseUnitValue baseUnitValue: Double) -> Double { constant / baseUnitValue }
    }
}

/// Data transfer rates, in bits per second at base.
public final class UnitDataRate: Dimension, @unchecked Sendable {
    public override class func baseUnit() -> Self {
        UnitConverter.Extra.bitsPerSecond as! Self
    }
}

/// Counts of things, so "30 in dozens" converts; "each" is one item.
final class UnitCount: Dimension, @unchecked Sendable {
    static let each = UnitCount(symbol: "each", converter: UnitConverterLinear(coefficient: 1))
    static let dozen = UnitCount(symbol: "dozen", converter: UnitConverterLinear(coefficient: 12))
    static let gross = UnitCount(symbol: "gross", converter: UnitConverterLinear(coefficient: 144))

    override class func baseUnit() -> UnitCount { each }
}
