import Foundation

/// CSS and design units: px, rem, em, pt, pc, and the physical in, cm and mm they relate to.
/// "2rem in px", "32px in rem", "12pt in px", "2 inches in px at 72 ppi", "1.5rem in px at 18px".
///
/// CSS fixes 1in = 96px, 1pt = 1/72in and 1pc = 12pt; rem and em are 16px unless "at <n>px" sets
/// the base. "at <n> ppi" (or dpi) switches to print and design math, where a pixel is 1/n inch.
/// At least one side must be a screen unit, so "1 pt in ml" stays pints for `UnitConverter`.
public enum ScreenUnits {
    private enum Unit: String {
        case px, rem, em, pt, pc, inch = "in", cm, mm

        var isScreen: Bool { [.px, .rem, .em, .pt, .pc].contains(self) }
        var symbol: String { self == .inch ? "in" : rawValue }
    }

    private static let names: [String: Unit] = [
        "px": .px, "pixel": .px, "pixels": .px, "rem": .rem, "rems": .rem, "em": .em, "ems": .em,
        "pt": .pt, "point": .pt, "points": .pt, "pc": .pc, "pica": .pc, "picas": .pc,
        "in": .inch, "inch": .inch, "inches": .inch, "cm": .cm, "mm": .mm
    ]
    private static let pattern = try! NSRegularExpression(pattern:
        #"^([0-9.,]+)\s*([a-z]+)\s+(?:in|to|as)\s+([a-z]+)(?:\s+at\s+([0-9.,]+)\s*(ppi|dpi|px))?$"#)

    public static func evaluate(_ text: String, locale: Locale = .current) -> CalculationAnswer? {
        let input = text.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
        let query = input.lowercased()
        guard let match = pattern.firstMatch(in: query, range: NSRange(query.startIndex..., in: query)) else { return nil }
        func part(_ index: Int) -> String? { Range(match.range(at: index), in: query).map { String(query[$0]) } }
        guard let amountText = part(1), let value = NumberLiteral.parse(amountText, locale: locale, magnitudes: false),
              let from = part(2).flatMap({ names[$0] }), let to = part(3).flatMap({ names[$0] }),
              from != to, from.isScreen || to.isScreen else { return nil }
        var base = 16.0, pixelsPerInch = 96.0
        var assumption: String?
        if let settingText = part(4), let setting = NumberLiteral.parse(settingText, locale: locale, magnitudes: false), setting > 0 {
            if part(5) == "px" {
                guard [from, to].contains(.rem) || [from, to].contains(.em) else { return nil }
                base = setting
                assumption = "1\(from == .em || to == .em ? "em" : "rem") = \(Calculator.format(setting, locale: locale))px"
            } else {
                pixelsPerInch = setting
                assumption = "\(Calculator.format(setting, locale: locale)) \(part(5)!)"
            }
        } else if part(4) != nil {
            return nil
        }
        func pixels(_ unit: Unit) -> Double {
            switch unit {
            case .px: return 1
            case .rem, .em: return base
            case .inch: return pixelsPerInch
            case .pt: return pixelsPerInch / 72
            case .pc: return pixelsPerInch / 6
            case .cm: return pixelsPerInch / 2.54
            case .mm: return pixelsPerInch / 25.4
            }
        }
        let result = value * pixels(from) / pixels(to)
        let rounded = (result * 10_000).rounded() / 10_000
        let text = Calculator.format(rounded, locale: locale) + to.symbol
        let detail = assumption ?? ([from, to].contains(.rem) ? "1rem = 16px" : [from, to].contains(.em) ? "1em = 16px" : "96px per inch")
        return CalculationAnswer(input: input, inputDetail: detail, result: text, resultDetail: nil, copyText: text)
    }
}
