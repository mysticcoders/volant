import Foundation

/// A color sampled from the screen, in sRGB components from 0 to 1, written out in the formats a
/// designer pastes most. Formatting is the calculator's, so a picked color and a typed one read
/// the same.
public struct PickedColor: Equatable, Hashable {
    public let red: Double, green: Double, blue: Double

    /// Clamps each component to 0...1, since a sampler can report values just outside sRGB.
    public init(red: Double, green: Double, blue: Double) {
        self.red = min(max(red, 0), 1)
        self.green = min(max(green, 0), 1)
        self.blue = min(max(blue, 0), 1)
    }

    public enum Format: String, CaseIterable, Identifiable, Hashable {
        case hex, rgb, hsl, oklch
        public var id: String { rawValue }
        /// The format's name as a designer would say it; CSS names stay in English.
        public var label: String { rawValue == "oklch" ? "OKLCH" : rawValue.uppercased() }

        var calculatorFormat: ColorCalculator.Format {
            switch self {
            case .hex: return .hex
            case .rgb: return .rgb
            case .hsl: return .hsl
            case .oklch: return .oklch
            }
        }
    }

    /// The color as CSS text in one format, such as `#ff6363` or `rgb(255 99 99)`.
    public func value(_ format: Format) -> String {
        ColorCalculator.format(ColorCalculator.Color(red: red, green: green, blue: blue, alpha: 1), as: format.calculatorFormat)
    }
}
