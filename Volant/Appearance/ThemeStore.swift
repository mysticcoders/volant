import AppKit
import SwiftUI
import VolantCore

/// The active color theme resolved to SwiftUI and AppKit colors. A theme without a palette keeps
/// macOS materials and semantic colors; its accent is nil for System (the macOS accent color) or
/// Volant's rust in light and dark variants.
struct ResolvedTheme: Equatable {
    let id: String
    let palette: ColorPalette?
    let accentPair: ColorTheme.Accent?

    static let system = ResolvedTheme(ColorTheme.named(ColorTheme.systemID))

    init(_ theme: ColorTheme) {
        id = theme.id
        palette = theme.palette
        accentPair = theme.accent
    }

    var hasPalette: Bool { palette != nil }

    /// The accent for tinting, or nil to leave the macOS accent color in place.
    var accent: Color? {
        if let palette { return Color(hex: palette.accent) }
        return nsAccent.map(Color.init(nsColor:))
    }

    /// The accent as an NSColor that resolves its light or dark variant at draw time.
    var nsAccent: NSColor? {
        if let palette { return NSColor(hex: palette.accent) }
        guard let pair = accentPair, let light = NSColor(hex: pair.light), let dark = NSColor(hex: pair.dark) else { return nil }
        return NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? dark : light
        }
    }

    /// The accent for AppKit drawing, falling back on the macOS accent color.
    var resolvedNSAccent: NSColor { nsAccent ?? .controlAccentColor }

    /// The window background behind every hosted surface, solid so light and dark render reliably.
    var windowBackground: Color {
        palette.flatMap { Color(hex: $0.background) } ?? Color(nsColor: .windowBackgroundColor)
    }

    /// The launcher and notes surface: the palette background, or the system material.
    func surface(opacity: Double) -> AnyShapeStyle {
        if let palette, let color = Color(hex: palette.background) { return AnyShapeStyle(color.opacity(opacity)) }
        return AnyShapeStyle(.regularMaterial.opacity(opacity))
    }

    /// Popovers and bars drawn above the surface.
    var raisedSurface: AnyShapeStyle {
        if let palette, let color = Color(hex: palette.secondaryBackground) { return AnyShapeStyle(color) }
        return AnyShapeStyle(.regularMaterial)
    }

    /// The highlighted row: the palette's selection color, or the accent at low strength.
    var selection: AnyShapeStyle {
        if let palette, let color = Color(hex: palette.selection) { return AnyShapeStyle(color) }
        return AnyShapeStyle(.tint.opacity(0.14))
    }

    /// A card's resting and selected fills. Palettes use their own layers instead of a gray wash.
    func card(selected: Bool) -> AnyShapeStyle {
        if let palette, let color = Color(hex: selected ? palette.selection : palette.secondaryBackground) {
            return AnyShapeStyle(color)
        }
        return AnyShapeStyle(Color.primary.opacity(selected ? 0.10 : 0.05))
    }

    /// Hairlines and outlines at the given system strength.
    func separator(_ systemOpacity: Double) -> Color {
        if let palette, let color = Color(hex: palette.separator) { return color }
        return Color.primary.opacity(systemOpacity)
    }

    /// Primary and secondary text styles for palette surfaces.
    var textStyles: (AnyShapeStyle, AnyShapeStyle) {
        if let palette, let text = Color(hex: palette.text), let secondary = Color(hex: palette.secondaryText) {
            return (AnyShapeStyle(text), AnyShapeStyle(secondary))
        }
        return (AnyShapeStyle(.primary), AnyShapeStyle(.secondary))
    }
}

/// Publishes the configured theme so every hosted surface restyles when Settings changes it.
@MainActor
final class ThemeStore: ObservableObject {
    static let shared = ThemeStore()
    @Published private(set) var theme = ResolvedTheme.system

    /// Resolves the appearance block's color theme and pins the app's light or dark appearance
    /// when the theme or the appearance setting asks for one.
    func apply(_ appearance: Appearance) {
        let resolved = ResolvedTheme(appearance.resolvedColorTheme)
        if resolved != theme { theme = resolved }
        switch appearance.effectiveMode {
        case nil: NSApp.appearance = nil
        case .light: NSApp.appearance = NSAppearance(named: .aqua)
        case .dark: NSApp.appearance = NSAppearance(named: .darkAqua)
        }
    }
}

private struct VolantThemeKey: EnvironmentKey {
    static let defaultValue = ResolvedTheme.system
}

extension EnvironmentValues {
    var volantTheme: ResolvedTheme {
        get { self[VolantThemeKey.self] }
        set { self[VolantThemeKey.self] = newValue }
    }
}

/// Root wrapper for a hosted surface: supplies the theme, its accent as the tint, and on palette
/// surfaces the palette's text colors. Settings passes `paletteText: false` so its system-drawn
/// form keeps semantic text on system backgrounds.
struct ThemedRoot<Content: View>: View {
    @ObservedObject private var store = ThemeStore.shared
    private let paletteText: Bool
    private let content: Content

    init(paletteText: Bool = true, @ViewBuilder content: () -> Content) {
        self.paletteText = paletteText
        self.content = content()
    }

    var body: some View {
        let theme = store.theme
        let styles = paletteText ? theme.textStyles : (AnyShapeStyle(.primary), AnyShapeStyle(.secondary))
        content
            .environment(\.volantTheme, theme)
            .tint(theme.accent)
            .foregroundStyle(styles.0, styles.1)
    }
}

extension Color {
    /// A color from a `#rrggbb` string.
    init?(hex: String) {
        guard let (r, g, b) = ColorPalette.components(hex) else { return nil }
        self.init(.sRGB, red: r, green: g, blue: b, opacity: 1)
    }
}

extension NSColor {
    /// An sRGB color from a `#rrggbb` string.
    convenience init?(hex: String) {
        guard let (r, g, b) = ColorPalette.components(hex) else { return nil }
        self.init(srgbRed: r, green: g, blue: b, alpha: 1)
    }
}
