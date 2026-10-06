import Foundation

/// CSS colors converted between formats: hex (`#rgb`, `#rgba`, `#rrggbb`, `#rrggbbaa`), `rgb()`,
/// `hsl()`, `hwb()`, `lab()`, `lch()`, `oklab()` and `oklch()`, in legacy comma or modern space
/// syntax with an optional `/ alpha`. "#ff6363 in oklch" picks the target; otherwise hex answers
/// in rgb and everything else in hex, tagged with a second format.
///
/// Conversions follow CSS Color 4: sRGB with its transfer curve, lab/lch relative to D50 through
/// the Bradford transform, and OKLab from linear sRGB. Colors outside sRGB keep their exact values
/// in lab, lch, oklab and oklch, and show their nearest sRGB color elsewhere, tagged "Outside
/// sRGB". The 148 CSS named colors answer only with a target ("rebeccapurple in hex"), and hex
/// needs its `#`, since bare names and digits read as ordinary words and numbers.
public enum ColorCalculator {
    /// sRGB components, gamma-encoded and unclamped, so colors outside sRGB survive conversion.
    struct Color: Equatable {
        var red: Double, green: Double, blue: Double, alpha: Double
    }

    enum Format: String, CaseIterable {
        case hex, rgb, hsl, hwb, lab, lch, oklab, oklch
    }

    private static let target = try! NSRegularExpression(pattern:
        #"^(.+?)\s+(?:in|to|as)\s+(hex|rgba?|hsla?|hwb|lab|lch|oklab|oklch)$"#)

    public static func evaluate(_ text: String) -> CalculationAnswer? {
        let input = text.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
        let query = input.lowercased()
        guard query.utf8.count <= 128 else { return nil }
        var colorText = query, requested: Format?
        if let match = target.firstMatch(in: query, range: NSRange(query.startIndex..., in: query)),
           let colorRange = Range(match.range(at: 1), in: query), let formatRange = Range(match.range(at: 2), in: query) {
            colorText = String(query[colorRange])
            let name = String(query[formatRange])
            requested = Format(rawValue: ["rgba": "rgb", "hsla": "hsl"][name] ?? name)
        }
        let namedValue = requested == nil ? nil : NamedColors.values[colorText.replacingOccurrences(of: " ", with: "")]
        let named = namedValue.map { value in
            (Color(red: Double(value >> 16 & 0xff) / 255, green: Double(value >> 8 & 0xff) / 255, blue: Double(value & 0xff) / 255, alpha: 1), Format.hex)
        }
        guard let (color, source) = parse(colorText) ?? named else { return nil }
        let primary = requested ?? (source == .hex ? .rgb : .hex)
        let secondary: Format = primary == .hex ? (source == .rgb ? .hsl : .rgb) : (primary == .rgb ? .hsl : .hex)
        let result = format(color, as: primary)
        var detail = format(color, as: secondary)
        if !inGamut(color) && [.hex, .rgb, .hsl, .hwb].contains(primary) { detail = "Outside sRGB · " + detail }
        let shown = clamped(color)
        return CalculationAnswer(input: input, inputDetail: named == nil ? nil : format(color, as: .hex), result: result,
                                 resultDetail: detail, copyText: result,
                                 swatch: .init(red: shown.red, green: shown.green, blue: shown.blue, alpha: shown.alpha),
                                 swapQuery: named == nil && primary != source ? "\(result) in \(source.rawValue)" : nil)
    }

    // MARK: Parsing

    static func parse(_ text: String) -> (Color, Format)? {
        if text.hasPrefix("#") { return hex(String(text.dropFirst())).map { ($0, .hex) } }
        guard let open = text.firstIndex(of: "("), text.hasSuffix(")") else { return nil }
        var name = String(text[..<open]).trimmingCharacters(in: .whitespaces)
        if ["rgba", "hsla"].contains(name) { name.removeLast() }
        guard let format = Format(rawValue: name), format != .hex else { return nil }
        let body = text[text.index(after: open)..<text.index(before: text.endIndex)]
        guard let (values, alpha) = arguments(String(body)), values.count == 3 else { return nil }
        let color: Color?
        switch format {
        case .rgb: color = rgb(values)
        case .hsl: color = hsl(values)
        case .hwb: color = hwb(values)
        case .lab: color = lab(values)
        case .lch: color = lch(values)
        case .oklab: color = oklab(values)
        case .oklch: color = oklch(values)
        case .hex: color = nil
        }
        guard var parsed = color else { return nil }
        if let alpha {
            guard let value = alpha.number(percentOf: 1), (0...1).contains(value) else { return nil }
            parsed.alpha = value
        }
        return (parsed, format)
    }

    private static func hex(_ digits: String) -> Color? {
        guard [3, 4, 6, 8].contains(digits.count), digits.allSatisfy(\.isHexDigit) else { return nil }
        let full = digits.count <= 4 ? digits.map { "\($0)\($0)" }.joined() : digits
        let bytes = stride(from: 0, to: full.count, by: 2).compactMap { offset -> Double? in
            let start = full.index(full.startIndex, offsetBy: offset)
            return UInt8(full[start..<full.index(start, offsetBy: 2)], radix: 16).map { Double($0) / 255 }
        }
        return Color(red: bytes[0], green: bytes[1], blue: bytes[2], alpha: bytes.count == 4 ? bytes[3] : 1)
    }

    /// One CSS argument: a number, a percentage, or a hue with an angle unit.
    struct Argument {
        let value: Double
        let unit: String

        func number(percentOf scale: Double) -> Double? {
            switch unit {
            case "": return value
            case "%": return value / 100 * scale
            default: return nil
            }
        }

        var hue: Double? {
            switch unit {
            case "", "deg": return value
            case "rad": return value * 180 / .pi
            case "grad": return value * 0.9
            case "turn": return value * 360
            default: return nil
            }
        }
    }

    /// Splits "255, 99, 99, 0.5" or "255 99 99 / 50%" into three channels and an optional alpha.
    private static func arguments(_ body: String) -> ([Argument], Argument?)? {
        let slash = body.split(separator: "/", omittingEmptySubsequences: false)
        guard slash.count <= 2 else { return nil }
        let commas = body.contains(",")
        let separators: (Character) -> Bool = { $0 == "," || $0.isWhitespace }
        var parts = slash[0].split(whereSeparator: separators).map(String.init)
        var alpha = slash.count == 2 ? slash[1].split(whereSeparator: separators).map(String.init) : []
        if commas, slash.count == 1, parts.count == 4 { alpha = [parts.removeLast()] }
        guard alpha.count <= 1 else { return nil }
        let values = parts.compactMap(argument)
        guard values.count == parts.count else { return nil }
        if let text = alpha.first {
            guard let value = argument(text) else { return nil }
            return (values, value)
        }
        return (values, nil)
    }

    private static func argument(_ text: String) -> Argument? {
        guard let split = text.firstIndex(where: { $0.isLetter || $0 == "%" }) else { return Double(text).map { Argument(value: $0, unit: "") } }
        guard let value = Double(text[..<split]) else { return nil }
        let unit = String(text[split...])
        return ["%", "deg", "rad", "grad", "turn"].contains(unit) ? Argument(value: value, unit: unit) : nil
    }

    private static func rgb(_ v: [Argument]) -> Color? {
        guard let r = v[0].number(percentOf: 255), let g = v[1].number(percentOf: 255), let b = v[2].number(percentOf: 255) else { return nil }
        return Color(red: r / 255, green: g / 255, blue: b / 255, alpha: 1)
    }

    private static func hsl(_ v: [Argument]) -> Color? {
        guard let h = v[0].hue, let s = v[1].number(percentOf: 100), let l = v[2].number(percentOf: 100) else { return nil }
        let (r, g, b) = hslToRGB(h, s / 100, l / 100)
        return Color(red: r, green: g, blue: b, alpha: 1)
    }

    private static func hwb(_ v: [Argument]) -> Color? {
        guard let h = v[0].hue, var white = v[1].number(percentOf: 100), var black = v[2].number(percentOf: 100) else { return nil }
        white /= 100; black /= 100
        if white + black >= 1 { let gray = white / (white + black); return Color(red: gray, green: gray, blue: gray, alpha: 1) }
        let (r, g, b) = hslToRGB(h, 1, 0.5)
        let scale = 1 - white - black
        return Color(red: r * scale + white, green: g * scale + white, blue: b * scale + white, alpha: 1)
    }

    private static func lab(_ v: [Argument]) -> Color? {
        guard let l = v[0].number(percentOf: 100), let a = v[1].number(percentOf: 125), let b = v[2].number(percentOf: 125) else { return nil }
        return fromLinear(xyzD65ToLinear(d50ToD65(labToXYZ(l, a, b))))
    }

    private static func lch(_ v: [Argument]) -> Color? {
        guard let l = v[0].number(percentOf: 100), let c = v[1].number(percentOf: 150), let h = v[2].hue else { return nil }
        let radians = h * .pi / 180
        return fromLinear(xyzD65ToLinear(d50ToD65(labToXYZ(l, c * cos(radians), c * sin(radians)))))
    }

    private static func oklab(_ v: [Argument]) -> Color? {
        guard let l = v[0].number(percentOf: 1), let a = v[1].number(percentOf: 0.4), let b = v[2].number(percentOf: 0.4) else { return nil }
        return fromLinear(oklabToLinear(l, a, b))
    }

    private static func oklch(_ v: [Argument]) -> Color? {
        guard let l = v[0].number(percentOf: 1), let c = v[1].number(percentOf: 0.4), let h = v[2].hue else { return nil }
        let radians = h * .pi / 180
        return fromLinear(oklabToLinear(l, c * cos(radians), c * sin(radians)))
    }

    // MARK: Formatting

    static func format(_ color: Color, as format: Format) -> String {
        let alpha = color.alpha < 1 ? " / \(trim(color.alpha, 3))" : ""
        let srgb = clamped(color)
        switch format {
        case .hex:
            let bytes = [srgb.red, srgb.green, srgb.blue] + (color.alpha < 1 ? [color.alpha] : [])
            return "#" + bytes.map { String(format: "%02x", Int(($0 * 255).rounded())) }.joined()
        case .rgb:
            let channels = [srgb.red, srgb.green, srgb.blue].map { String(Int(($0 * 255).rounded())) }
            return "rgb(\(channels.joined(separator: " "))\(alpha))"
        case .hsl:
            let (h, s, l) = rgbToHSL(srgb)
            return "hsl(\(trim(h, 1)) \(trim(s * 100, 1))% \(trim(l * 100, 1))%\(alpha))"
        case .hwb:
            let (h, _, _) = rgbToHSL(srgb)
            let white = min(srgb.red, srgb.green, srgb.blue), black = 1 - max(srgb.red, srgb.green, srgb.blue)
            return "hwb(\(trim(h, 1)) \(trim(white * 100, 1))% \(trim(black * 100, 1))%\(alpha))"
        case .lab:
            let (l, a, b) = xyzToLab(d65ToD50(linearToXYZD65(toLinear(color))))
            return "lab(\(trim(l, 2))% \(trim(a, 2)) \(trim(b, 2))\(alpha))"
        case .lch:
            let (l, a, b) = xyzToLab(d65ToD50(linearToXYZD65(toLinear(color))))
            let (c, h) = polar(a, b, epsilon: 0.0015)
            return "lch(\(trim(l, 2))% \(trim(c, 2)) \(trim(h, 2))\(alpha))"
        case .oklab:
            let (l, a, b) = linearToOklab(toLinear(color))
            return "oklab(\(trim(l * 100, 1))% \(trim(a, 4)) \(trim(b, 4))\(alpha))"
        case .oklch:
            let (l, a, b) = linearToOklab(toLinear(color))
            let (c, h) = polar(a, b, epsilon: 0.000004)
            return "oklch(\(trim(l * 100, 1))% \(trim(c, 4)) \(trim(h, 2))\(alpha))"
        }
    }

    /// Fixed decimals without trailing zeros, always with a period as CSS requires.
    private static func trim(_ value: Double, _ places: Int) -> String {
        var text = String(format: "%.\(places)f", locale: Locale(identifier: "en_US_POSIX"), value)
        if text.contains(".") { while text.hasSuffix("0") { text.removeLast() }; if text.hasSuffix(".") { text.removeLast() } }
        return text == "-0" ? "0" : text
    }

    /// Chroma and hue; hue is 0 for colors with effectively no chroma.
    private static func polar(_ a: Double, _ b: Double, epsilon: Double) -> (Double, Double) {
        let chroma = (a * a + b * b).squareRoot()
        guard chroma > epsilon else { return (0, 0) }
        let hue = atan2(b, a) * 180 / .pi
        return (chroma, hue < 0 ? hue + 360 : hue)
    }

    // MARK: Color math

    static func inGamut(_ c: Color) -> Bool {
        [c.red, c.green, c.blue].allSatisfy { $0 >= -0.0005 && $0 <= 1.0005 }
    }

    static func clamped(_ c: Color) -> Color {
        Color(red: min(max(c.red, 0), 1), green: min(max(c.green, 0), 1), blue: min(max(c.blue, 0), 1), alpha: c.alpha)
    }

    private static func hslToRGB(_ hue: Double, _ s: Double, _ l: Double) -> (Double, Double, Double) {
        let h = (hue.truncatingRemainder(dividingBy: 360) + 360).truncatingRemainder(dividingBy: 360)
        func f(_ n: Double) -> Double {
            let k = (n + h / 30).truncatingRemainder(dividingBy: 12)
            return l - s * min(l, 1 - l) * max(-1, min(k - 3, 9 - k, 1))
        }
        return (f(0), f(8), f(4))
    }

    private static func rgbToHSL(_ c: Color) -> (Double, Double, Double) {
        let maxValue = max(c.red, c.green, c.blue), minValue = min(c.red, c.green, c.blue)
        let l = (maxValue + minValue) / 2, d = maxValue - minValue
        guard d > 0 else { return (0, 0, l) }
        let s = d / (1 - abs(2 * l - 1))
        var h: Double
        switch maxValue {
        case c.red: h = (c.green - c.blue) / d + (c.green < c.blue ? 6 : 0)
        case c.green: h = (c.blue - c.red) / d + 2
        default: h = (c.red - c.green) / d + 4
        }
        h *= 60
        return (h >= 359.95 ? 0 : h, s, l)
    }

    private static func toLinear(_ c: Color) -> [Double] {
        [c.red, c.green, c.blue].map { v in
            let sign: Double = v < 0 ? -1 : 1, x = abs(v)
            return sign * (x <= 0.04045 ? x / 12.92 : pow((x + 0.055) / 1.055, 2.4))
        }
    }

    private static func fromLinear(_ v: [Double], alpha: Double = 1) -> Color {
        let e = v.map { value -> Double in
            let sign: Double = value < 0 ? -1 : 1, x = abs(value)
            return sign * (x <= 0.0031308 ? 12.92 * x : 1.055 * pow(x, 1 / 2.4) - 0.055)
        }
        return Color(red: e[0], green: e[1], blue: e[2], alpha: alpha)
    }

    private static func multiply(_ m: [[Double]], _ v: [Double]) -> [Double] {
        m.map { row in zip(row, v).reduce(0) { $0 + $1.0 * $1.1 } }
    }

    private static func linearToXYZD65(_ v: [Double]) -> [Double] {
        multiply([[0.41239079926595934, 0.357584339383878, 0.1804807884018343],
                  [0.21263900587151027, 0.715168678767756, 0.07219231536073371],
                  [0.01933081871559182, 0.11919477979462598, 0.9505321522496607]], v)
    }

    private static func xyzD65ToLinear(_ v: [Double]) -> [Double] {
        multiply([[3.2409699419045226, -1.537383177570094, -0.4986107602930034],
                  [-0.9692436362808796, 1.8759675015077202, 0.04155505740717559],
                  [0.05563007969699366, -0.20397695888897652, 1.0569715142428786]], v)
    }

    private static func d65ToD50(_ v: [Double]) -> [Double] {
        multiply([[1.0479298208405488, 0.022946793341019088, -0.05019222954313557],
                  [0.029627815688159344, 0.990434484573249, -0.01707382502938514],
                  [-0.009243058152591178, 0.015055144896577895, 0.7518742899580008]], v)
    }

    private static func d50ToD65(_ v: [Double]) -> [Double] {
        multiply([[0.9554734527042182, -0.023098536874261423, 0.0632593086610217],
                  [-0.028369706963208136, 1.0099954580058226, 0.021041398966943008],
                  [0.012314001688319899, -0.020507696433477912, 1.3303659366080753]], v)
    }

    private static let whiteD50 = [0.3457 / 0.3585, 1, (1 - 0.3457 - 0.3585) / 0.3585]
    private static let epsilon = 216.0 / 24389, kappa = 24389.0 / 27

    private static func xyzToLab(_ xyz: [Double]) -> (Double, Double, Double) {
        let f = zip(xyz, whiteD50).map { value, white -> Double in
            let v = value / white
            return v > epsilon ? cbrt(v) : (kappa * v + 16) / 116
        }
        return (116 * f[1] - 16, 500 * (f[0] - f[1]), 200 * (f[1] - f[2]))
    }

    private static func labToXYZ(_ l: Double, _ a: Double, _ b: Double) -> [Double] {
        let f1 = (l + 16) / 116, f0 = a / 500 + f1, f2 = f1 - b / 200
        let x = pow(f0, 3) > epsilon ? pow(f0, 3) : (116 * f0 - 16) / kappa
        let y = l > kappa * epsilon ? pow(f1, 3) : l / kappa
        let z = pow(f2, 3) > epsilon ? pow(f2, 3) : (116 * f2 - 16) / kappa
        return zip([x, y, z], whiteD50).map { $0 * $1 }
    }

    private static func linearToOklab(_ v: [Double]) -> (Double, Double, Double) {
        let lms = multiply([[0.4122214708, 0.5363325363, 0.0514459929],
                            [0.2119034982, 0.6806995451, 0.1073969566],
                            [0.0883024619, 0.2817188376, 0.6299787005]], v).map(cbrt)
        let lab = multiply([[0.2104542553, 0.7936177850, -0.0040720468],
                            [1.9779984951, -2.4285922050, 0.4505937099],
                            [0.0259040371, 0.7827717662, -0.8086757660]], lms)
        return (lab[0], lab[1], lab[2])
    }

    private static func oklabToLinear(_ l: Double, _ a: Double, _ b: Double) -> [Double] {
        let lms = multiply([[1, 0.3963377774, 0.2158037573],
                            [1, -0.1055613458, -0.0638541728],
                            [1, -0.0894841775, -1.2914855480]], [l, a, b]).map { $0 * $0 * $0 }
        return multiply([[4.0767416621, -3.3077115913, 0.2309699292],
                         [-1.2684380046, 2.6097574011, -0.3413193965],
                         [-0.0041960863, -0.7034186147, 1.7076147010]], lms)
    }
}
