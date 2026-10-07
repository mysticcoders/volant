import Foundation

/// Kitchen conversions between volume and weight for common ingredients ("1 cup flour in grams",
/// "250 g sugar in cups", "2 tbsp butter in g", "1 stick of butter in grams"), and gas marks
/// ("gas mark 4 in c", "350f in gas mark").
///
/// Weights per volume come from King Arthur Baking's Ingredient Weight Chart
/// (https://www.kingarthurbaking.com/learn/ingredient-weight-chart, read October 2026), kept in the
/// chart's own measure so the card can quote it ("Table salt · 18 g per tbsp"). Water alone uses its
/// physical density of 1 g per mL, since the chart rounds liquids to 8 oz a cup. Cups, tablespoons
/// and teaspoons are US customary, as in the unit converter; `metric cup` is 250 mL. An ingredient
/// the table does not know gives no answer rather than a guess.
public enum CookingConverter {
    struct Ingredient {
        let name: String
        let grams: Double
        let cups: Double
        let measure: String
        let aliases: [String]

        var gramsPerCup: Double { grams / cups }
        var reference: String { name == "Water" ? "1 g per mL" : "\(formatGrams(grams)) g per \(measure)" }
        var primary: String { aliases[0] }
    }

    struct Unit {
        let milliliters: Double?
        let grams: Double?
        let singular: String
        let plural: String
        let butterOnly: Bool
        let spoon: Bool

        func label(_ value: Double) -> String { value == 1 ? singular : plural }
    }

    static let cupMilliliters = 236.5882365

    /// The chart's entries, by grams for the measure it lists, as a fraction of a US cup.
    static let ingredients: [Ingredient] = [
        Ingredient(name: "All-purpose flour", grams: 120, cups: 1, measure: "cup",
                   aliases: ["all-purpose flour", "flour", "all purpose flour", "allpurpose flour", "ap flour", "plain flour",
                             "white flour", "unbleached flour"]),
        Ingredient(name: "Bread flour", grams: 120, cups: 1, measure: "cup", aliases: ["bread flour", "strong flour"]),
        Ingredient(name: "Whole wheat flour", grams: 113, cups: 1, measure: "cup",
                   aliases: ["whole wheat flour", "wholewheat flour", "wholemeal flour"]),
        Ingredient(name: "Cake flour", grams: 120, cups: 1, measure: "cup", aliases: ["cake flour"]),
        Ingredient(name: "Self-rising flour", grams: 113, cups: 1, measure: "cup",
                   aliases: ["self-rising flour", "self rising flour", "self raising flour"]),
        Ingredient(name: "Almond flour", grams: 96, cups: 1, measure: "cup", aliases: ["almond flour"]),
        Ingredient(name: "Rye flour", grams: 106, cups: 1, measure: "cup", aliases: ["rye flour", "medium rye flour"]),
        Ingredient(name: "Semolina", grams: 163, cups: 1, measure: "cup", aliases: ["semolina", "semolina flour"]),
        Ingredient(name: "Cornmeal", grams: 138, cups: 1, measure: "cup", aliases: ["cornmeal", "corn meal"]),
        Ingredient(name: "Rice flour", grams: 142, cups: 1, measure: "cup", aliases: ["rice flour", "white rice flour"]),
        Ingredient(name: "Coconut flour", grams: 128, cups: 1, measure: "cup", aliases: ["coconut flour"]),
        Ingredient(name: "Granulated sugar", grams: 198, cups: 1, measure: "cup",
                   aliases: ["sugar", "granulated sugar", "white sugar"]),
        Ingredient(name: "Superfine sugar", grams: 190, cups: 1, measure: "cup",
                   aliases: ["superfine sugar", "caster sugar", "castor sugar"]),
        Ingredient(name: "Brown sugar, packed", grams: 213, cups: 1, measure: "cup",
                   aliases: ["brown sugar", "packed brown sugar", "brown sugar packed", "light brown sugar", "dark brown sugar"]),
        Ingredient(name: "Powdered sugar", grams: 113, cups: 1, measure: "cup",
                   aliases: ["powdered sugar", "confectioners sugar", "confectioner sugar", "icing sugar"]),
        Ingredient(name: "Turbinado sugar", grams: 180, cups: 1, measure: "cup", aliases: ["turbinado sugar", "raw sugar"]),
        Ingredient(name: "Demerara sugar", grams: 220, cups: 1, measure: "cup", aliases: ["demerara sugar", "demerara"]),
        Ingredient(name: "Butter", grams: 113, cups: 0.5, measure: "stick", aliases: ["butter", "unsalted butter", "salted butter"]),
        Ingredient(name: "Water", grams: cupMilliliters, cups: 1, measure: "cup", aliases: ["water"]),
        Ingredient(name: "Milk", grams: 227, cups: 1, measure: "cup", aliases: ["milk", "whole milk", "skim milk", "fresh milk"]),
        Ingredient(name: "Buttermilk", grams: 227, cups: 1, measure: "cup", aliases: ["buttermilk"]),
        Ingredient(name: "Heavy cream", grams: 227, cups: 1, measure: "cup",
                   aliases: ["heavy cream", "cream", "whipping cream", "heavy whipping cream", "light cream", "half and half",
                             "double cream"]),
        Ingredient(name: "Sour cream", grams: 227, cups: 1, measure: "cup", aliases: ["sour cream"]),
        Ingredient(name: "Yogurt", grams: 227, cups: 1, measure: "cup", aliases: ["yogurt", "yoghurt", "plain yogurt"]),
        Ingredient(name: "Cream cheese", grams: 227, cups: 1, measure: "cup", aliases: ["cream cheese"]),
        Ingredient(name: "Vegetable oil", grams: 198, cups: 1, measure: "cup",
                   aliases: ["vegetable oil", "oil", "canola oil", "sunflower oil"]),
        Ingredient(name: "Olive oil", grams: 50, cups: 0.25, measure: "¼ cup", aliases: ["olive oil", "extra virgin olive oil"]),
        Ingredient(name: "Coconut oil", grams: 113, cups: 0.5, measure: "½ cup", aliases: ["coconut oil"]),
        Ingredient(name: "Vegetable shortening", grams: 46, cups: 0.25, measure: "¼ cup", aliases: ["shortening", "vegetable shortening"]),
        Ingredient(name: "Honey", grams: 21, cups: 1.0 / 16, measure: "tbsp", aliases: ["honey"]),
        Ingredient(name: "Maple syrup", grams: 156, cups: 0.5, measure: "½ cup", aliases: ["maple syrup"]),
        Ingredient(name: "Corn syrup", grams: 312, cups: 1, measure: "cup", aliases: ["corn syrup"]),
        Ingredient(name: "Molasses", grams: 85, cups: 0.25, measure: "¼ cup", aliases: ["molasses"]),
        Ingredient(name: "Sweetened condensed milk", grams: 78, cups: 0.25, measure: "¼ cup",
                   aliases: ["sweetened condensed milk", "condensed milk"]),
        Ingredient(name: "Peanut butter", grams: 135, cups: 0.5, measure: "½ cup", aliases: ["peanut butter"]),
        Ingredient(name: "Rice, long grain, dry", grams: 99, cups: 0.5, measure: "½ cup",
                   aliases: ["rice", "long grain rice", "white rice", "uncooked rice", "dry rice"]),
        Ingredient(name: "Rolled oats", grams: 89, cups: 1, measure: "cup",
                   aliases: ["rolled oats", "oats", "old fashioned oats", "quick oats", "oatmeal"]),
        Ingredient(name: "Steel-cut oats", grams: 70, cups: 0.5, measure: "½ cup", aliases: ["steel-cut oats", "steel cut oats"]),
        Ingredient(name: "Cocoa powder", grams: 42, cups: 0.5, measure: "½ cup",
                   aliases: ["cocoa powder", "cocoa", "unsweetened cocoa", "unsweetened cocoa powder"]),
        Ingredient(name: "Table salt", grams: 18, cups: 1.0 / 16, measure: "tbsp", aliases: ["table salt", "salt", "fine salt"]),
        Ingredient(name: "Kosher salt, Diamond Crystal", grams: 8, cups: 1.0 / 16, measure: "tbsp",
                   aliases: ["diamond crystal kosher salt", "diamond crystal salt", "diamond crystal", "kosher salt diamond crystal"]),
        Ingredient(name: "Kosher salt, Morton", grams: 16, cups: 1.0 / 16, measure: "tbsp",
                   aliases: ["morton kosher salt", "mortons kosher salt", "morton salt", "kosher salt morton"]),
        Ingredient(name: "Baking powder", grams: 4, cups: 1.0 / 48, measure: "tsp", aliases: ["baking powder"]),
        Ingredient(name: "Baking soda", grams: 3, cups: 1.0 / 96, measure: "½ tsp", aliases: ["baking soda", "bicarbonate of soda"]),
        Ingredient(name: "Instant yeast", grams: 9, cups: 1.0 / 16, measure: "tbsp", aliases: ["instant yeast", "yeast"]),
        Ingredient(name: "Cornstarch", grams: 28, cups: 0.25, measure: "¼ cup", aliases: ["cornstarch", "corn starch"]),
        Ingredient(name: "Chocolate chips", grams: 170, cups: 1, measure: "cup",
                   aliases: ["chocolate chips", "chocolate chip", "choc chips", "semisweet chocolate chips"]),
        Ingredient(name: "Walnuts, chopped", grams: 113, cups: 1, measure: "cup", aliases: ["walnuts", "chopped walnuts"]),
        Ingredient(name: "Pecans, diced", grams: 57, cups: 0.5, measure: "½ cup", aliases: ["pecans", "chopped pecans", "diced pecans"]),
        Ingredient(name: "Pecans, whole", grams: 105, cups: 1, measure: "cup", aliases: ["whole pecans"]),
        Ingredient(name: "Almonds, sliced", grams: 43, cups: 0.5, measure: "½ cup", aliases: ["sliced almonds"]),
        Ingredient(name: "Almonds, whole", grams: 142, cups: 1, measure: "cup", aliases: ["almonds", "whole almonds"]),
        Ingredient(name: "Raisins", grams: 149, cups: 1, measure: "cup", aliases: ["raisins"]),
        Ingredient(name: "Shredded coconut", grams: 85, cups: 1, measure: "cup",
                   aliases: ["shredded coconut", "coconut", "sweetened coconut", "desiccated coconut"])
    ]

    /// Names that match more than one entry, answered with one card each instead of a guess:
    /// a tablespoon of Morton kosher salt weighs twice one of Diamond Crystal.
    static let ambiguous: [String: [String]] = [
        "kosher salt": ["Kosher salt, Diamond Crystal", "Kosher salt, Morton"]
    ]

    private static let aliasTable: [String: Ingredient] = {
        var table: [String: Ingredient] = [:]
        for ingredient in ingredients {
            for alias in ingredient.aliases { table[normalize(alias)] = ingredient }
        }
        return table
    }()

    private static let units: [String: Unit] = {
        var table: [String: Unit] = [:]
        func volume(_ names: [String], _ ml: Double, _ singular: String, _ plural: String, spoon: Bool = false, butter: Bool = false) {
            for name in names {
                table[name] = Unit(milliliters: ml, grams: nil, singular: singular, plural: plural, butterOnly: butter, spoon: spoon)
            }
        }
        func mass(_ names: [String], _ grams: Double, _ symbol: String) {
            for name in names {
                table[name] = Unit(milliliters: nil, grams: grams, singular: symbol, plural: symbol, butterOnly: false, spoon: false)
            }
        }
        volume(["cup", "cups"], cupMilliliters, "cup", "cups")
        volume(["metriccup", "metriccups"], 250, "metric cup", "metric cups")
        volume(["tbsp", "tbs", "tablespoon", "tablespoons"], 14.78676478125, "tbsp", "tbsp", spoon: true)
        volume(["tsp", "teaspoon", "teaspoons"], 4.92892159375, "tsp", "tsp", spoon: true)
        volume(["ml", "milliliter", "milliliters", "millilitre", "millilitres"], 1, "mL", "mL")
        volume(["l", "liter", "liters", "litre", "litres"], 1000, "L", "L")
        volume(["floz", "fluidounce", "fluidounces"], 29.5735295625, "fl oz", "fl oz")
        volume(["pt", "pint", "pints"], 473.176473, "pt", "pt")
        volume(["qt", "quart", "quarts"], 946.352946, "qt", "qt")
        volume(["stick", "sticks"], cupMilliliters / 2, "stick", "sticks", butter: true)
        mass(["g", "gram", "grams", "gramme", "grammes"], 1, "g")
        mass(["kg", "kilogram", "kilograms"], 1000, "kg")
        mass(["mg", "milligram", "milligrams"], 0.001, "mg")
        mass(["oz", "ounce", "ounces"], 28.349523125, "oz")
        mass(["lb", "lbs", "pound", "pounds"], 453.59237, "lb")
        return table
    }()

    /// The first answer for a kitchen conversion or gas mark, if the query is one.
    public static func evaluate(_ text: String, locale: Locale = .current) -> CalculationAnswer? {
        evaluateAll(text, locale: locale).first
    }

    /// Every answer for the query: one card normally, one per entry when an ingredient name is
    /// ambiguous ("kosher salt").
    public static func evaluateAll(_ text: String, locale: Locale = .current) -> [CalculationAnswer] {
        let input = text.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
        let query = input.lowercased()
        guard !query.isEmpty, query.utf8.count <= 96 else { return [] }
        if let gas = gasMark(query, input: input, locale: locale) { return [gas] }
        for separator in [" in ", " to ", " as "] {
            var search = query.startIndex
            while let range = query.range(of: separator, range: search..<query.endIndex) {
                search = query.index(after: range.lowerBound)
                guard let target = unit(String(query[range.upperBound...])),
                      let (amount, rest) = amount(String(query[..<range.lowerBound]), locale: locale),
                      let (source, name) = sourceAndIngredient(rest) else { continue }
                let found = ingredients(named: name, source: source)
                let answers = found.compactMap {
                    answer(amount: amount, source: source, target: target, ingredient: $0, input: input, locale: locale)
                }
                if !answers.isEmpty { return answers }
            }
        }
        return []
    }

    /// The ingredient or ingredients a name refers to; a stick with no name is butter.
    private static func ingredients(named name: String, source: Unit) -> [Ingredient] {
        let key = normalize(name)
        if key.isEmpty { return source.butterOnly ? ingredients.filter { $0.name == "Butter" } : [] }
        if let names = ambiguous[key] { return ingredients.filter { names.contains($0.name) } }
        if let found = aliasTable[key] { return [found] }
        if key.hasSuffix("s"), let found = aliasTable[String(key.dropLast())] { return [found] }
        return []
    }

    /// Builds the card: weight from volume or volume from weight through the ingredient's grams
    /// per cup, or a plain conversion when both units measure the same thing. Sticks are only for butter.
    private static func answer(amount: Double, source: Unit, target: Unit, ingredient: Ingredient, input: String,
                               locale: Locale) -> CalculationAnswer? {
        if (source.butterOnly || target.butterOnly), ingredient.name != "Butter" { return nil }
        let result: Double
        var weighed = true
        switch (source.milliliters, source.grams, target.milliliters, target.grams) {
        case let (ml?, nil, nil, g?):
            result = amount * ml / cupMilliliters * ingredient.gramsPerCup / g
        case let (nil, g?, ml?, nil):
            result = amount * g / ingredient.gramsPerCup * cupMilliliters / ml
        case let (from?, nil, to?, nil):
            result = amount * from / to
            weighed = false
        case let (nil, from?, nil, to?):
            result = amount * from / to
            weighed = false
        default:
            return nil
        }
        guard result.isFinite, result > 0 else { return nil }
        let rounded = kitchenRound(result)
        let number = Calculator.format(rounded, locale: locale)
        let text = "\(number) \(target.label(rounded))"
        let friendly = target.milliliters != nil ? kitchenFraction(result, unit: target) : nil
        let plain = friendly == "\(number) \(target.label(rounded))"
        let detail = plain ? (weighed ? "Approximate" : nil) : friendly.map { "About \($0)" } ?? (weighed ? "Approximate" : nil)
        let swap = "\(number) \(target.label(rounded)) \(ingredient.primary) in \(source.plural)"
        return CalculationAnswer(input: input, inputDetail: "\(ingredient.name) · \(ingredient.reference)", result: text,
                                 resultDetail: detail, copyText: text, swapQuery: swap)
    }

    /// Splits "cup of flour", "tbsp butter" or "sticks" into the measuring unit and the
    /// ingredient's name, trying two-word units ("fl oz", "metric cup") before one-word ones.
    private static func sourceAndIngredient(_ rest: String) -> (Unit, String)? {
        let words = rest.split(separator: " ").map(String.init)
        for count in [2, 1] where words.count >= count {
            guard let found = units[words[..<count].joined()] else { continue }
            var name = Array(words[count...])
            if name.first == "of" { name.removeFirst() }
            return (found, name.joined(separator: " "))
        }
        return nil
    }

    private static func unit(_ text: String) -> Unit? {
        units[text.filter { !$0.isWhitespace }]
    }

    private static let vulgar: [Character: Double] = ["¼": 0.25, "½": 0.5, "¾": 0.75, "⅓": 1.0 / 3, "⅔": 2.0 / 3, "⅛": 0.125,
                                                      "⅜": 0.375, "⅝": 0.625, "⅞": 0.875]

    /// Reads the leading amount the way recipes write it: "2", "1.5", "1/2", "1 1/2", "1½",
    /// "½", or "a"/"an"/"one" for a single measure ("a cup of flour"). Returns it with the text after it.
    static func amount(_ text: String, locale: Locale) -> (Double, String)? {
        for word in ["a ", "an ", "one "] where text.hasPrefix(word) {
            return (1, String(text.dropFirst(word.count)))
        }
        let chars = Array(text)
        let separators = NumberLiteral.Separators(locale)
        var value = 0.0
        var index = 0
        if let (whole, end) = NumberLiteral.scan(chars, from: 0, separators, magnitudes: false)
            ?? NumberLiteral.scan(chars, from: 0, separators, magnitudes: false, grouping: false) {
            value = whole
            index = end
            if index < chars.count, chars[index] == "/" {
                guard let (denominator, next) = NumberLiteral.scan(chars, from: index + 1, separators, magnitudes: false, grouping: false),
                      denominator > 0, whole == whole.rounded(), denominator == denominator.rounded() else { return nil }
                value = whole / denominator
                index = next
            } else if index + 1 < chars.count, chars[index] == " ", whole == whole.rounded(),
                      let (numerator, slash) = NumberLiteral.scan(chars, from: index + 1, separators, magnitudes: false, grouping: false),
                      slash < chars.count, chars[slash] == "/",
                      let (denominator, next) = NumberLiteral.scan(chars, from: slash + 1, separators, magnitudes: false, grouping: false),
                      denominator > numerator, numerator == numerator.rounded(), denominator == denominator.rounded() {
                value += numerator / denominator
                index = next
            } else {
                let after = index < chars.count && chars[index] == " " ? index + 1 : index
                if after < chars.count, let part = vulgar[chars[after]], whole == whole.rounded() {
                    value += part
                    index = after + 1
                }
            }
        } else if let first = chars.first, let part = vulgar[first] {
            value = part
            index = 1
        } else {
            return nil
        }
        guard value > 0 else { return nil }
        let rest = String(chars[index...]).trimmingCharacters(in: .whitespaces)
        return rest.isEmpty ? nil : (value, rest)
    }

    /// Kitchen answers are approximate, so they keep three significant digits, and whole units
    /// from 100 up: 120 g, 4.23 oz, 1.27 cups.
    static func kitchenRound(_ value: Double) -> Double {
        if value >= 100 { return value.rounded() }
        let scale = pow(10, 2 - floor(log10(value)))
        return (value * scale).rounded() / scale
    }

    /// The measure a cook would reach for: cups and sticks to the nearest eighth or quarter, spoons
    /// to the nearest quarter ("1 ¼ cups", "¾ tsp"); nil for metric units or a result that rounds to nothing.
    static func kitchenFraction(_ value: Double, unit: Unit) -> String? {
        let steps: Double
        switch unit.singular {
        case "cup", "metric cup": steps = 8
        case "stick": steps = 4
        case _ where unit.spoon: steps = 4
        default: return nil
        }
        let nearest = (value * steps).rounded() / steps
        guard nearest > 0 else { return nil }
        let whole = floor(nearest)
        let part = nearest - whole
        let glyphs: [Double: String] = [0.125: "⅛", 0.25: "¼", 0.375: "⅜", 0.5: "½", 0.625: "⅝", 0.75: "¾", 0.875: "⅞"]
        let fraction = glyphs[part] ?? ""
        let number = whole == 0 ? fraction : (fraction.isEmpty ? "\(Int(whole))" : "\(Int(whole)) \(fraction)")
        return "\(number) \(nearest > 1 ? unit.plural : unit.singular)"
    }

    /// Lowercases and drops punctuation so "Confectioners' sugar", "all-purpose flour" and
    /// "Brown Sugar (packed)" match their aliases.
    static func normalize(_ name: String) -> String {
        let cleaned = name.lowercased().map { character -> Character in
            character == "-" || character == "(" || character == ")" || character == "," ? " " : character
        }.filter { $0 != "'" && $0 != "’" }
        return String(cleaned).split(separator: " ").joined(separator: " ")
    }

    private static func formatGrams(_ grams: Double) -> String {
        grams == grams.rounded() ? String(Int(grams)) : String(grams)
    }

    /// The UK gas mark scale, as °F: ¼ is 225, ½ is 250, and each mark from 1 to 10 adds 25 to 250.
    static let gasMarks: [(Double, Double)] = [(0.25, 225), (0.5, 250)] + (1...10).map { (Double($0), 250 + 25 * Double($0)) }

    private static let toTemperature = try! NSRegularExpression(pattern: #"^gas\s*mark\s*([0-9]+|1/2|1/4|½|¼)\s+(?:in|to|as)\s+°?\s*(f|c|fahrenheit|celsius)$"#)
    private static let toGasMark = try! NSRegularExpression(pattern: #"^(-?[0-9][0-9.,]*)\s*(?:°|degrees?\s*)?\s*(f|c|fahrenheit|celsius)\s+(?:in|to|as)\s+gas\s*marks?$"#)

    /// "gas mark 4 in c" gives the temperature, rounded to a whole degree; "350f in gas mark"
    /// gives the nearest mark, saying so when the temperature falls between marks.
    private static func gasMark(_ query: String, input: String, locale: Locale) -> CalculationAnswer? {
        let range = NSRange(query.startIndex..., in: query)
        if let match = toTemperature.firstMatch(in: query, range: range),
           let markRange = Range(match.range(at: 1), in: query), let scaleRange = Range(match.range(at: 2), in: query) {
            let markText = String(query[markRange])
            let mark: Double? = ["1/2": 0.5, "½": 0.5, "1/4": 0.25, "¼": 0.25][markText] ?? Double(markText)
            guard let mark, let fahrenheit = gasMarks.first(where: { $0.0 == mark })?.1 else { return nil }
            let celsius = query[scaleRange].hasPrefix("c")
            let degrees = celsius ? ((fahrenheit - 32) * 5 / 9).rounded() : fahrenheit
            let text = "\(Calculator.format(degrees, locale: locale)) °\(celsius ? "C" : "F")"
            return CalculationAnswer(input: input, inputDetail: celsius ? "Gas mark \(markLabel(mark)) = \(Int(fahrenheit)) °F" : nil, result: text,
                                     resultDetail: celsius ? "Rounded to a whole degree" : nil, copyText: text,
                                     swapQuery: "\(Calculator.format(degrees, locale: locale)) \(celsius ? "c" : "f") in gas mark")
        }
        guard let match = toGasMark.firstMatch(in: query, range: range),
              let valueRange = Range(match.range(at: 1), in: query), let scaleRange = Range(match.range(at: 2), in: query),
              let value = NumberLiteral.parse(String(query[valueRange]), locale: locale, magnitudes: false) else { return nil }
        let fahrenheit = query[scaleRange].hasPrefix("c") ? value * 9 / 5 + 32 : value
        guard let nearest = gasMarks.min(by: { abs($0.1 - fahrenheit) < abs($1.1 - fahrenheit) }),
              abs(nearest.1 - fahrenheit) <= 12.5 else { return nil }
        let text = "Gas mark \(markLabel(nearest.0))"
        let exact = abs(nearest.1 - fahrenheit) < 0.5
        return CalculationAnswer(input: input, inputDetail: nil, result: text,
                                 resultDetail: exact ? "\(Int(nearest.1)) °F" : "Nearest mark · \(Int(nearest.1)) °F", copyText: text,
                                 swapQuery: "gas mark \(markLabel(nearest.0, ascii: true)) in \(query[scaleRange].hasPrefix("c") ? "c" : "f")")
    }

    private static func markLabel(_ mark: Double, ascii: Bool = false) -> String {
        switch mark {
        case 0.25: return ascii ? "1/4" : "¼"
        case 0.5: return ascii ? "1/2" : "½"
        default: return String(Int(mark))
        }
    }
}
