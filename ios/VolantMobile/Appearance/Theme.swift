import SwiftUI
import UIKit
import VolantCore

/// The active VolantCore color theme resolved to SwiftUI colors, mirroring the Mac app's
/// ResolvedTheme. A theme without a palette keeps iOS materials and semantic colors; its accent
/// is nil for System (the iOS tint) or Volant's rust in light and dark variants.
struct ResolvedTheme: Equatable {
    let id: String
    let mode: ColorTheme.Mode?
    let palette: ColorPalette?
    let accentPair: ColorTheme.Accent?

    static let defaultID = "volant"

    init(_ theme: ColorTheme) {
        id = theme.id
        mode = theme.mode
        palette = theme.palette
        accentPair = theme.accent
    }

    /// The accent for tinting, or nil to leave the system tint in place.
    var accent: Color? {
        if let palette { return Color(hex: palette.accent) }
        guard let pair = accentPair, let light = UIColor(hex: pair.light), let dark = UIColor(hex: pair.dark) else { return nil }
        return Color(uiColor: UIColor { $0.userInterfaceStyle == .dark ? dark : light })
    }

    /// The light or dark scheme a palette theme forces, or nil to follow the system.
    var colorScheme: ColorScheme? {
        switch mode {
        case .light: .light
        case .dark: .dark
        case nil: nil
        }
    }

    /// The page behind every surface: the palette background, or the grouped system background.
    var background: Color {
        palette.flatMap { Color(hex: $0.background) } ?? Color(uiColor: .systemBackground)
    }

    /// Rows, cards and bars drawn above the background.
    var raisedSurface: Color {
        palette.flatMap { Color(hex: $0.secondaryBackground) } ?? Color(uiColor: .secondarySystemBackground)
    }

    /// Primary and secondary text on palette surfaces, or the semantic styles.
    var textStyles: (AnyShapeStyle, AnyShapeStyle) {
        if let palette, let text = Color(hex: palette.text), let secondary = Color(hex: palette.secondaryText) {
            return (AnyShapeStyle(text), AnyShapeStyle(secondary))
        }
        return (AnyShapeStyle(.primary), AnyShapeStyle(.secondary))
    }

    var hasPalette: Bool { palette != nil }
}

/// Publishes the chosen theme, persisted by identifier the same way the Mac config stores it.
@MainActor
final class ThemeStore: ObservableObject {
    @AppStorage("colorTheme") private var storedID = ResolvedTheme.defaultID
    @Published private(set) var theme: ResolvedTheme

    init() {
        let id = UserDefaults.standard.string(forKey: "colorTheme") ?? ResolvedTheme.defaultID
        theme = ResolvedTheme(ColorTheme.named(id))
    }

    var themes: [ColorTheme] { ColorTheme.catalog }

    func select(_ id: String) {
        storedID = id
        theme = ResolvedTheme(ColorTheme.named(id))
    }
}

private struct VolantThemeKey: EnvironmentKey {
    static let defaultValue = ResolvedTheme(ColorTheme.named(ResolvedTheme.defaultID))
}

extension EnvironmentValues {
    var volantTheme: ResolvedTheme {
        get { self[VolantThemeKey.self] }
        set { self[VolantThemeKey.self] = newValue }
    }
}

/// Root wrapper: supplies the theme, its accent as the tint, its forced appearance, and on
/// palette themes the palette's text colors.
struct ThemedRoot<Content: View>: View {
    @ObservedObject var store: ThemeStore
    @ViewBuilder var content: Content

    var body: some View {
        let theme = store.theme
        content
            .environment(\.volantTheme, theme)
            .tint(theme.accent)
            .preferredColorScheme(theme.colorScheme)
    }
}

extension Color {
    /// An sRGB color from a `#rrggbb` string.
    init?(hex: String) {
        guard let (r, g, b) = ColorPalette.components(hex) else { return nil }
        self.init(.sRGB, red: r, green: g, blue: b, opacity: 1)
    }
}

extension UIColor {
    /// An sRGB color from a `#rrggbb` string.
    convenience init?(hex: String) {
        guard let (r, g, b) = ColorPalette.components(hex) else { return nil }
        self.init(red: r, green: g, blue: b, alpha: 1)
    }
}
