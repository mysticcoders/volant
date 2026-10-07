import Foundation

/// The colors a named theme paints Volant's own surfaces with, as `#rrggbb` strings. Background is
/// the launcher and notes surface, secondary background the popovers and cards, selection the
/// highlighted row, and separator the hairlines. The remaining colors are the palette's semantic hues.
public struct ColorPalette: Codable, Equatable {
    public var background: String
    public var secondaryBackground: String
    public var text: String
    public var secondaryText: String
    public var selection: String
    public var accent: String
    public var separator: String
    public var red: String
    public var orange: String
    public var yellow: String
    public var green: String
    public var blue: String
    public var purple: String

    public init(background: String, secondaryBackground: String, text: String, secondaryText: String, selection: String,
                accent: String, separator: String, red: String, orange: String, yellow: String, green: String,
                blue: String, purple: String) {
        self.background = background
        self.secondaryBackground = secondaryBackground
        self.text = text
        self.secondaryText = secondaryText
        self.selection = selection
        self.accent = accent
        self.separator = separator
        self.red = red
        self.orange = orange
        self.yellow = yellow
        self.green = green
        self.blue = blue
        self.purple = purple
    }

    /// Every color in a fixed order, for validation.
    public var all: [String] {
        [background, secondaryBackground, text, secondaryText, selection, accent, separator, red, orange, yellow, green, blue, purple]
    }

    /// Whether every color is a six-digit hex color.
    public var isValid: Bool { all.allSatisfy { ColorPalette.components($0) != nil } }

    /// The 0–1 sRGB channels of a `#rrggbb` string, or nil when it is not one.
    public static func components(_ hex: String) -> (red: Double, green: Double, blue: Double)? {
        let digits = hex.hasPrefix("#") ? hex.dropFirst() : Substring(hex)
        guard digits.count == 6, let value = UInt32(digits, radix: 16) else { return nil }
        return (Double(value >> 16 & 0xFF) / 255, Double(value >> 8 & 0xFF) / 255, Double(value & 0xFF) / 255)
    }

    /// The WCAG 2 contrast ratio between two `#rrggbb` colors, from 1 to 21.
    public static func contrast(_ first: String, _ second: String) -> Double? {
        guard let a = luminance(first), let b = luminance(second) else { return nil }
        return (max(a, b) + 0.05) / (min(a, b) + 0.05)
    }

    /// WCAG 2 relative luminance of a `#rrggbb` color.
    private static func luminance(_ hex: String) -> Double? {
        guard let (r, g, b) = components(hex) else { return nil }
        func linear(_ c: Double) -> Double { c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4) }
        return 0.2126 * linear(r) + 0.7152 * linear(g) + 0.0722 * linear(b)
    }
}

/// A color theme: System uses macOS materials and the system accent color, Volant the same
/// materials with Volant's rust accent, and every other theme a fixed palette in one appearance.
/// A theme with a mode decides light or dark itself; the others follow the appearance setting.
public struct ColorTheme: Equatable, Identifiable {
    public enum Mode: String, Codable { case light, dark }

    /// An accent with a light and a dark variant, for themes that follow the appearance setting.
    public struct Accent: Equatable {
        public let light: String
        public let dark: String
    }

    public let id: String
    public let name: String
    public let mode: Mode?
    public let palette: ColorPalette?
    public let accent: Accent?

    public init(id: String, name: String, mode: Mode?, palette: ColorPalette?, accent: Accent? = nil) {
        self.id = id
        self.name = name
        self.mode = mode
        self.palette = palette
        self.accent = accent
    }

    public static let systemID = "system"

    /// The theme with this identifier, or System when it is unknown.
    public static func named(_ id: String) -> ColorTheme {
        catalog.first { $0.id == id } ?? catalog[0]
    }

    /// Built-in themes in picker order. Palette values come from each project's published palette;
    /// docs/color-themes.md lists the sources and licenses.
    public static let catalog: [ColorTheme] = [
        ColorTheme(id: systemID, name: "System", mode: nil, palette: nil),
        ColorTheme(id: "volant", name: "Volant", mode: nil, palette: nil, accent: Accent(light: "#c73c2a", dark: "#ff7a5f")),
        ColorTheme(id: "catppuccin-latte", name: "Catppuccin Latte", mode: .light, palette: ColorPalette(
            background: "#eff1f5", secondaryBackground: "#e6e9ef", text: "#4c4f69", secondaryText: "#5c5f77",
            selection: "#ccd0da", accent: "#8839ef", separator: "#bcc0cc", red: "#d20f39", orange: "#fe640b",
            yellow: "#df8e1d", green: "#40a02b", blue: "#1e66f5", purple: "#8839ef")),
        ColorTheme(id: "catppuccin-frappe", name: "Catppuccin Frappé", mode: .dark, palette: ColorPalette(
            background: "#303446", secondaryBackground: "#292c3c", text: "#c6d0f5", secondaryText: "#b5bfe2",
            selection: "#414559", accent: "#ca9ee6", separator: "#51576d", red: "#e78284", orange: "#ef9f76",
            yellow: "#e5c890", green: "#a6d189", blue: "#8caaee", purple: "#ca9ee6")),
        ColorTheme(id: "catppuccin-macchiato", name: "Catppuccin Macchiato", mode: .dark, palette: ColorPalette(
            background: "#24273a", secondaryBackground: "#1e2030", text: "#cad3f5", secondaryText: "#b8c0e0",
            selection: "#363a4f", accent: "#c6a0f6", separator: "#494d64", red: "#ed8796", orange: "#f5a97f",
            yellow: "#eed49f", green: "#a6da95", blue: "#8aadf4", purple: "#c6a0f6")),
        ColorTheme(id: "catppuccin-mocha", name: "Catppuccin Mocha", mode: .dark, palette: ColorPalette(
            background: "#1e1e2e", secondaryBackground: "#181825", text: "#cdd6f4", secondaryText: "#bac2de",
            selection: "#313244", accent: "#cba6f7", separator: "#45475a", red: "#f38ba8", orange: "#fab387",
            yellow: "#f9e2af", green: "#a6e3a1", blue: "#89b4fa", purple: "#cba6f7")),
        ColorTheme(id: "nord", name: "Nord", mode: .dark, palette: ColorPalette(
            background: "#2e3440", secondaryBackground: "#3b4252", text: "#eceff4", secondaryText: "#d8dee9",
            selection: "#434c5e", accent: "#88c0d0", separator: "#4c566a", red: "#bf616a", orange: "#d08770",
            yellow: "#ebcb8b", green: "#a3be8c", blue: "#81a1c1", purple: "#b48ead")),
        ColorTheme(id: "dracula", name: "Dracula", mode: .dark, palette: ColorPalette(
            background: "#282a36", secondaryBackground: "#21222c", text: "#f8f8f2", secondaryText: "#bfbfbf",
            selection: "#44475a", accent: "#bd93f9", separator: "#44475a", red: "#ff5555", orange: "#ffb86c",
            yellow: "#f1fa8c", green: "#50fa7b", blue: "#8be9fd", purple: "#bd93f9")),
        ColorTheme(id: "gruvbox-dark", name: "Gruvbox Dark", mode: .dark, palette: ColorPalette(
            background: "#282828", secondaryBackground: "#32302f", text: "#ebdbb2", secondaryText: "#bdae93",
            selection: "#504945", accent: "#fabd2f", separator: "#504945", red: "#fb4934", orange: "#fe8019",
            yellow: "#fabd2f", green: "#b8bb26", blue: "#83a598", purple: "#d3869b")),
        ColorTheme(id: "gruvbox-light", name: "Gruvbox Light", mode: .light, palette: ColorPalette(
            background: "#fbf1c7", secondaryBackground: "#f2e5bc", text: "#3c3836", secondaryText: "#504945",
            selection: "#ebdbb2", accent: "#af3a03", separator: "#d5c4a1", red: "#9d0006", orange: "#af3a03",
            yellow: "#b57614", green: "#79740e", blue: "#076678", purple: "#8f3f71")),
        ColorTheme(id: "solarized-dark", name: "Solarized Dark", mode: .dark, palette: ColorPalette(
            background: "#002b36", secondaryBackground: "#073642", text: "#93a1a1", secondaryText: "#839496",
            selection: "#073642", accent: "#268bd2", separator: "#586e75", red: "#dc322f", orange: "#cb4b16",
            yellow: "#b58900", green: "#859900", blue: "#268bd2", purple: "#6c71c4")),
        ColorTheme(id: "solarized-light", name: "Solarized Light", mode: .light, palette: ColorPalette(
            background: "#fdf6e3", secondaryBackground: "#eee8d5", text: "#073642", secondaryText: "#586e75",
            selection: "#eee8d5", accent: "#268bd2", separator: "#93a1a1", red: "#dc322f", orange: "#cb4b16",
            yellow: "#b58900", green: "#859900", blue: "#268bd2", purple: "#6c71c4")),
        ColorTheme(id: "tokyo-night", name: "Tokyo Night", mode: .dark, palette: ColorPalette(
            background: "#1a1b26", secondaryBackground: "#16161e", text: "#c0caf5", secondaryText: "#a9b1d6",
            selection: "#292e42", accent: "#7aa2f7", separator: "#3b4261", red: "#f7768e", orange: "#ff9e64",
            yellow: "#e0af68", green: "#9ece6a", blue: "#7aa2f7", purple: "#bb9af7")),
        ColorTheme(id: "rose-pine", name: "Rosé Pine", mode: .dark, palette: ColorPalette(
            background: "#191724", secondaryBackground: "#1f1d2e", text: "#e0def4", secondaryText: "#908caa",
            selection: "#26233a", accent: "#c4a7e7", separator: "#403d52", red: "#eb6f92", orange: "#ebbcba",
            yellow: "#f6c177", green: "#9ccfd8", blue: "#31748f", purple: "#c4a7e7")),
        ColorTheme(id: "rose-pine-dawn", name: "Rosé Pine Dawn", mode: .light, palette: ColorPalette(
            background: "#faf4ed", secondaryBackground: "#fffaf3", text: "#575279", secondaryText: "#6e6a86",
            selection: "#f2e9e1", accent: "#907aa9", separator: "#dfdad9", red: "#b4637a", orange: "#d7827e",
            yellow: "#ea9d34", green: "#56949f", blue: "#286983", purple: "#907aa9")),
        ColorTheme(id: "one-dark", name: "One Dark", mode: .dark, palette: ColorPalette(
            background: "#282c34", secondaryBackground: "#21252b", text: "#abb2bf", secondaryText: "#9da5b4",
            selection: "#3e4451", accent: "#61afef", separator: "#3e4451", red: "#e06c75", orange: "#d19a66",
            yellow: "#e5c07b", green: "#98c379", blue: "#61afef", purple: "#c678dd"))
    ]
}
