import Foundation

/// Changes to a CSS color, answered as a new color: "#f00 lighten 10%", "darken", "saturate" and
/// "desaturate" (also "lighten(#f00, 10%)"), "complement of #3a7bd5", "#3a7bd5 at 50% alpha" or
/// "with 50% opacity", "mix(#f00, #00f)" or CSS "color-mix(in srgb, #f00 25%, #00f)", and the
/// WCAG contrast ratio of two colors, "contrast #fff #3a7bd5".
///
/// Lightness, saturation and the complement work in HSL with absolute steps, as Sass does, so
/// "#f00 lighten 10%" is hsl(0 100% 60%), #ff3333. Mixing follows CSS color-mix: OKLab unless
/// "in srgb" or "in srgb-linear" is given, premultiplied alpha, and percentages that are filled
/// in or scaled to 100 (a total under 100 lowers the alpha). Contrast treats the first color as
/// text on the second, composites a translucent background over white and translucent text over
/// the background, and floors the ratio to two decimals so a ratio just under 4.5 never reads as
/// passing. An adjustment answers in the color's own format, or the one after "in"; named colors
/// work because the operation word already marks the query as a color.
public enum ColorAdjustments {
    typealias Color = ColorCalculator.Color
    typealias Format = ColorCalculator.Format

    private static let target = try! NSRegularExpression(pattern:
        #"^(.+?)\s+(?:in|to|as)\s+(hex|rgba?|hsla?|hwb|lab|lch|oklab|oklch)$"#)
    private static let suffixStep = try! NSRegularExpression(pattern:
        #"^(.+?)\s+(lighten|darken|saturate|desaturate)\s+(?:by\s+)?(\d+(?:\.\d+)?)%$"#)
    private static let complement = try! NSRegularExpression(pattern: #"^complement(?:ary)?\s+(?:of\s+)?(.+)$"#)
    private static let alpha = try! NSRegularExpression(pattern:
        #"^(.+?)\s+(?:at|with)\s+(\d+(?:\.\d+)?)(%?)\s+(?:alpha|opacity)$"#)
    private static let contrast = try! NSRegularExpression(pattern:
        #"^contrast(?:\s+ratio)?(?:\s+(?:of|between|for))?\s+(.+)$"#)

    public static func evaluate(_ text: String, locale: Locale = .current) -> CalculationAnswer? {
        let input = text.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
        let query = input.lowercased()
        guard query.utf8.count <= 160 else { return nil }
        if let groups = match(contrast, query) { return contrastAnswer(input: input, pair: groups[0], locale: locale) }
        var body = query, requested: Format?
        if let groups = match(target, query) {
            body = groups[0]
            requested = Format(rawValue: ["rgba": "rgb", "hsla": "hsl"][groups[1]] ?? groups[1])
        }
        guard let (color, source, operation) = adjusted(body) else { return nil }
        let primary = requested ?? source
        let secondary: Format = primary == .hex ? .rgb : .hex
        let result = ColorCalculator.format(color, as: primary)
        var detail = ColorCalculator.format(color, as: secondary)
        if !ColorCalculator.inGamut(color) && [.hex, .rgb, .hsl, .hwb].contains(primary) { detail = "Outside sRGB · " + detail }
        let shown = ColorCalculator.clamped(color)
        return CalculationAnswer(input: input, inputDetail: operation, result: result, resultDetail: detail, copyText: result,
                                 swatch: .init(red: shown.red, green: shown.green, blue: shown.blue, alpha: shown.alpha))
    }

    /// The color an adjustment produces, the format to answer in, and a short description of the step.
    private static func adjusted(_ body: String) -> (Color, Format, String)? {
        if let groups = match(suffixStep, body), let amount = Double(groups[2]) {
            return step(groups[1], groups[0], amount)
        }
        if let groups = match(complement, body), let (color, format) = color(groups[0]) {
            return (rotated(color), format, "Hue +180°")
        }
        if body.hasSuffix(" complement"), let (color, format) = color(String(body.dropLast(" complement".count))) {
            return (rotated(color), format, "Hue +180°")
        }
        if let groups = match(alpha, body), let (color, format) = color(groups[0]), let amount = Double(groups[1]) {
            let value = groups[2] == "%" ? amount / 100 : amount
            guard (0...1).contains(value) else { return nil }
            var faded = color
            faded.alpha = value
            return (faded, format, "Alpha " + percent(value))
        }
        guard let open = body.firstIndex(of: "("), body.hasSuffix(")") else { return nil }
        let name = String(body[..<open]).trimmingCharacters(in: .whitespaces)
        let arguments = split(String(body[body.index(after: open)..<body.index(before: body.endIndex)]))
        switch name {
        case "lighten", "darken", "saturate", "desaturate":
            guard arguments.count == 2, arguments[1].hasSuffix("%"), let amount = Double(arguments[1].dropLast()) else { return nil }
            return step(name, arguments[0], amount)
        case "complement":
            guard arguments.count == 1, let (color, format) = color(arguments[0]) else { return nil }
            return (rotated(color), format, "Hue +180°")
        case "mix", "color-mix":
            return mix(arguments)
        default:
            return nil
        }
    }

    /// A Sass-style absolute HSL step: lightness or saturation moves by `amount` percentage points.
    private static func step(_ verb: String, _ colorText: String, _ amount: Double) -> (Color, Format, String)? {
        guard amount <= 100, let (color, format) = color(colorText) else { return nil }
        let base = ColorCalculator.clamped(color)
        let (h, saturation, lightness) = ColorCalculator.rgbToHSL(base)
        var s = saturation, l = lightness
        let change = amount / 100
        let label: String
        switch verb {
        case "lighten": l = min(l + change, 1); label = "Lightness +"
        case "darken": l = max(l - change, 0); label = "Lightness −"
        case "saturate": s = min(s + change, 1); label = "Saturation +"
        default: s = max(s - change, 0); label = "Saturation −"
        }
        let (r, g, b) = ColorCalculator.hslToRGB(h, s, l)
        return (Color(red: r, green: g, blue: b, alpha: color.alpha), format, label + percent(change) + " (HSL)")
    }

    /// The complement: the same color with its HSL hue turned half way round.
    private static func rotated(_ color: Color) -> Color {
        let (h, s, l) = ColorCalculator.rgbToHSL(ColorCalculator.clamped(color))
        let (r, g, b) = ColorCalculator.hslToRGB(h + 180, s, l)
        return Color(red: r, green: g, blue: b, alpha: color.alpha)
    }

    /// CSS color-mix: an optional "in <space>" argument, then two colors with optional percentages
    /// on either side of each.
    private static func mix(_ arguments: [String]) -> (Color, Format, String)? {
        var parts = arguments, space = "oklab"
        if let first = parts.first, first.hasPrefix("in ") {
            space = String(first.dropFirst(3)).trimmingCharacters(in: .whitespaces)
            parts.removeFirst()
        }
        guard ["oklab", "srgb", "srgb-linear"].contains(space), parts.count == 2,
              let (first, firstShare) = weighted(parts[0]), let (second, secondShare) = weighted(parts[1]) else { return nil }
        var p1 = firstShare, p2 = secondShare
        switch (p1, p2) {
        case (nil, nil): p1 = 0.5; p2 = 0.5
        case (let p?, nil): p2 = 1 - p
        case (nil, let p?): p1 = 1 - p
        default: break
        }
        guard let w1 = p1, let w2 = p2, w1 >= 0, w2 >= 0, w1 + w2 > 0 else { return nil }
        let total = w1 + w2
        var mixed = interpolate(first.0, second.0, weight: w2 / total, space: space)
        if total < 1 { mixed.alpha *= total }
        let name = ["oklab": "OKLab", "srgb": "sRGB", "srgb-linear": "linear sRGB"][space] ?? space
        return (mixed, first.1, "\(percent(w1 / total)) / \(percent(w2 / total)) in \(name)")
    }

    /// One color-mix argument: a color with an optional percentage before or after it.
    private static func weighted(_ text: String) -> ((Color, Format), Double?)? {
        let words = text.split(separator: " ").map(String.init)
        if let last = words.last, words.count > 1, last.hasSuffix("%"), let value = Double(last.dropLast()),
           let parsed = color(words.dropLast().joined(separator: " ")) {
            return (0...100).contains(value) ? (parsed, value / 100) : nil
        }
        if let first = words.first, words.count > 1, first.hasSuffix("%"), let value = Double(first.dropLast()),
           let parsed = color(words.dropFirst().joined(separator: " ")) {
            return (0...100).contains(value) ? (parsed, value / 100) : nil
        }
        return color(text).map { ($0, nil) }
    }

    /// Premultiplied interpolation from `a` toward `b` by `weight`, in the given space.
    private static func interpolate(_ a: Color, _ b: Color, weight: Double, space: String) -> Color {
        func components(_ c: Color) -> [Double] {
            switch space {
            case "srgb": return [c.red, c.green, c.blue]
            case "srgb-linear": return ColorCalculator.toLinear(c)
            default:
                let (l, x, y) = ColorCalculator.linearToOklab(ColorCalculator.toLinear(c))
                return [l, x, y]
            }
        }
        let alpha = a.alpha * (1 - weight) + b.alpha * weight
        guard alpha > 0 else { return Color(red: 0, green: 0, blue: 0, alpha: 0) }
        let mixed = zip(components(a), components(b)).map { ($0 * a.alpha * (1 - weight) + $1 * b.alpha * weight) / alpha }
        switch space {
        case "srgb": return Color(red: mixed[0], green: mixed[1], blue: mixed[2], alpha: alpha)
        case "srgb-linear": return ColorCalculator.fromLinear(mixed, alpha: alpha)
        default: return ColorCalculator.fromLinear(ColorCalculator.oklabToLinear(mixed[0], mixed[1], mixed[2]), alpha: alpha)
        }
    }

    /// The WCAG 2 contrast ratio of text (the first color) on a background (the second).
    private static func contrastAnswer(input: String, pair: String, locale: Locale) -> CalculationAnswer? {
        guard let (text, background) = colorPair(pair) else { return nil }
        let white = Color(red: 1, green: 1, blue: 1, alpha: 1)
        let ground = over(ColorCalculator.clamped(background), white)
        let ink = over(ColorCalculator.clamped(text), ground)
        let lighter = max(luminance(ink), luminance(ground)), darker = min(luminance(ink), luminance(ground))
        let ratio = ((lighter + 0.05) / (darker + 0.05) * 100).rounded(.down) / 100
        let answer = Calculator.format(ratio, locale: locale) + ":1"
        let verdict: String
        switch ratio {
        case 7...: verdict = "Passes AAA"
        case 4.5...: verdict = "Passes AA · AAA for large text"
        case 3...: verdict = "AA for large text only"
        default: verdict = "Fails AA"
        }
        return CalculationAnswer(input: input, inputDetail: "Text on background", result: answer, resultDetail: verdict,
                                 copyText: answer, swatch: .init(red: ink.red, green: ink.green, blue: ink.blue, alpha: 1))
    }

    /// Two colors written one after the other, optionally joined by "and", "on", "vs", "against" or
    /// a comma; the first split where both sides read as colors wins.
    private static func colorPair(_ text: String) -> (Color, Color)? {
        var joined = text
        for word in [" and ", " on ", " vs. ", " vs ", " against "] { joined = joined.replacingOccurrences(of: word, with: ", ") }
        var depth = 0
        for index in joined.indices {
            switch joined[index] {
            case "(": depth += 1
            case ")": depth -= 1
            case " " where depth == 0, "," where depth == 0:
                let left = joined[..<index].trimmingCharacters(in: CharacterSet(charactersIn: ", "))
                let right = joined[joined.index(after: index)...].trimmingCharacters(in: CharacterSet(charactersIn: ", "))
                if let first = color(left), let second = color(right) { return (first.0, second.0) }
            default: break
            }
        }
        return nil
    }

    /// Source-over compositing of an sRGB color on an opaque backdrop.
    private static func over(_ top: Color, _ bottom: Color) -> Color {
        let a = top.alpha
        return Color(red: top.red * a + bottom.red * (1 - a), green: top.green * a + bottom.green * (1 - a),
                     blue: top.blue * a + bottom.blue * (1 - a), alpha: 1)
    }

    /// WCAG relative luminance from linear sRGB.
    private static func luminance(_ color: Color) -> Double {
        let linear = ColorCalculator.toLinear(color)
        return 0.2126 * linear[0] + 0.7152 * linear[1] + 0.0722 * linear[2]
    }

    /// A color in any CSS syntax ColorCalculator reads, or a CSS named color answered as hex.
    private static func color(_ text: String) -> (Color, Format)? {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        if let parsed = ColorCalculator.parse(trimmed) { return parsed }
        guard let value = NamedColors.values[trimmed.replacingOccurrences(of: " ", with: "")] else { return nil }
        return (Color(red: Double(value >> 16 & 0xff) / 255, green: Double(value >> 8 & 0xff) / 255,
                      blue: Double(value & 0xff) / 255, alpha: 1), .hex)
    }

    /// Splits function arguments at top-level commas, leaving commas inside rgb(…) alone.
    private static func split(_ body: String) -> [String] {
        var parts: [String] = [], current = "", depth = 0
        for character in body {
            switch character {
            case "(": depth += 1; current.append(character)
            case ")": depth -= 1; current.append(character)
            case "," where depth == 0: parts.append(current.trimmingCharacters(in: .whitespaces)); current = ""
            default: current.append(character)
            }
        }
        parts.append(current.trimmingCharacters(in: .whitespaces))
        return parts
    }

    private static func percent(_ fraction: Double) -> String {
        var text = String(format: "%.1f", locale: Locale(identifier: "en_US_POSIX"), fraction * 100)
        if text.hasSuffix(".0") { text.removeLast(2) }
        return text + "%"
    }

    private static func match(_ pattern: NSRegularExpression, _ text: String) -> [String]? {
        guard let result = pattern.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) else { return nil }
        return (1..<result.numberOfRanges).map { index in
            Range(result.range(at: index), in: text).map { String(text[$0]) } ?? ""
        }
    }
}
