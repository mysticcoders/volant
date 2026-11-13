import SwiftUI

/// Volant's brand colors, taken from the app icon's folded wing: amber at the leading edge
/// running into the rust red the Mac app uses as its accent.
enum Brand {
    static let amber = Color(red: 1.0, green: 0.647, blue: 0.239)
    static let coral = Color(red: 1.0, green: 0.478, blue: 0.373)
    static let rust = Color(red: 0.882, green: 0.302, blue: 0.227)

    static let gradient = LinearGradient(colors: [amber, coral, rust], startPoint: .topLeading, endPoint: .bottomTrailing)

    static let privacyLine = String(localized: "No Volant account. No telemetry.")
}

/// The wing from the website's brand mark (brand-mark.svg), drawn on a 32-point grid and scaled to fit.
struct VolantMarkShape: Shape {
    func path(in rect: CGRect) -> Path {
        let scale = min(rect.width, rect.height) / 32
        let dx = rect.minX + (rect.width - 32 * scale) / 2, dy = rect.minY + (rect.height - 32 * scale) / 2
        func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: dx + x * scale, y: dy + y * scale) }
        var path = Path()
        path.move(to: p(3, 5))
        path.addCurve(to: p(15.7, 15.4), control1: p(8.5, 5.5), control2: p(12.4, 8.8))
        path.addCurve(to: p(29, 9.6), control1: p(20.5, 9.5), control2: p(25, 8.6))
        path.addCurve(to: p(22.2, 20.2), control1: p(27, 11.4), control2: p(24.5, 17.2))
        path.addCurve(to: p(13, 27), control1: p(20.4, 22.6), control2: p(16.3, 25.2))
        path.addCurve(to: p(10.9, 19.5), control1: p(13.4, 23.9), control2: p(12.5, 21.6))
        path.addCurve(to: p(3, 5), control1: p(6.6, 14.8), control2: p(3.8, 10.4))
        path.closeSubpath()
        return path
    }
}

/// The wing filled with the brand gradient.
struct VolantMark: View {
    var size: CGFloat = 28

    var body: some View {
        VolantMarkShape()
            .fill(Brand.gradient)
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}

/// The wing and the name, used as the Home title and in onboarding.
struct VolantWordmark: View {
    var size: CGFloat = 26

    var body: some View {
        HStack(spacing: size * 0.3) {
            VolantMark(size: size * 1.15)
            Text("Volant")
                .font(.system(size: size, weight: .bold, design: .rounded))
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Volant")
    }
}

/// The large wing for Settings and onboarding: the mark over a soft amber glow, inside two faint
/// rings that echo the wing's curve.
struct HeroMark: View {
    var size: CGFloat = 120
    @State private var glowing = false

    var body: some View {
        ZStack {
            Circle()
                .fill(RadialGradient(colors: [Brand.coral.opacity(0.35), .clear], center: .center, startRadius: 0, endRadius: size * 0.75))
                .frame(width: size * 1.6, height: size * 1.6)
                .scaleEffect(glowing ? 1.05 : 0.95)
            Circle()
                .strokeBorder(Brand.gradient.opacity(0.25), lineWidth: 1)
                .frame(width: size * 1.25, height: size * 1.25)
            Circle()
                .strokeBorder(Brand.gradient.opacity(0.12), lineWidth: 1)
                .frame(width: size * 1.55, height: size * 1.55)
            VolantMark(size: size * 0.7)
                .shadow(color: Brand.rust.opacity(0.45), radius: 18, y: 6)
        }
        .frame(width: size * 1.6, height: size * 1.6)
        .onAppear {
            withAnimation(.easeInOut(duration: 3).repeatForever(autoreverses: true)) { glowing = true }
        }
        .accessibilityHidden(true)
    }
}

/// The tools Volant brings to the phone, each with its own colored icon tile.
enum Tool: String, CaseIterable, Identifiable {
    case notes, snippets, quicklinks, calculator

    var id: String { rawValue }

    var title: String {
        switch self {
        case .notes: String(localized: "Notes")
        case .snippets: String(localized: "Snippets")
        case .quicklinks: String(localized: "Quicklinks")
        case .calculator: String(localized: "Calculator")
        }
    }

    var subtitle: String {
        switch self {
        case .notes: String(localized: "Markdown, synced with your Mac")
        case .snippets: String(localized: "Copy text you use often")
        case .quicklinks: String(localized: "Open links and searches")
        case .calculator: String(localized: "Math, units, dates and time zones")
        }
    }

    var symbol: String {
        switch self {
        case .notes: "note.text"
        case .snippets: "text.quote"
        case .quicklinks: "bolt.fill"
        case .calculator: "plus.forwardslash.minus"
        }
    }

    var colors: [Color] {
        switch self {
        case .notes: [Brand.amber, Brand.rust]
        case .snippets: [Color(red: 0.36, green: 0.69, blue: 1.0), Color(red: 0.16, green: 0.42, blue: 0.95)]
        case .quicklinks: [Color(red: 0.72, green: 0.52, blue: 1.0), Color(red: 0.45, green: 0.28, blue: 0.92)]
        case .calculator: [Color(red: 0.55, green: 0.56, blue: 0.6), Color(red: 0.3, green: 0.31, blue: 0.35)]
        }
    }
}

/// A rounded, gradient-filled tile with a tool's symbol, like an app icon in miniature.
struct ToolIcon: View {
    let tool: Tool
    var size: CGFloat = 36
    var symbol: String? = nil

    var body: some View {
        RoundedRectangle(cornerRadius: size * 0.27, style: .continuous)
            .fill(LinearGradient(colors: tool.colors, startPoint: .top, endPoint: .bottom))
            .overlay {
                Image(systemName: symbol ?? tool.symbol)
                    .font(.system(size: size * 0.46, weight: .semibold))
                    .foregroundStyle(.white)
            }
            .overlay {
                RoundedRectangle(cornerRadius: size * 0.27, style: .continuous)
                    .strokeBorder(.white.opacity(0.18), lineWidth: 0.5)
            }
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}

/// A brief confirmation pill shown at the bottom of a screen, such as after copying.
struct ToastModifier: ViewModifier {
    @Binding var message: String?

    func body(content: Content) -> some View {
        content
            .overlay(alignment: .bottom) {
                if let message {
                    Label(message, systemImage: "checkmark.circle.fill")
                        .font(.subheadline.weight(.semibold))
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .glassEffect(.regular, in: .capsule)
                        .padding(.bottom, 24)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                        .task(id: message) {
                            try? await Task.sleep(for: .seconds(1.6))
                            withAnimation { self.message = nil }
                        }
                }
            }
            .animation(.spring(duration: 0.35), value: message)
            .sensoryFeedback(.success, trigger: message) { _, new in new != nil }
    }
}

extension View {
    func toast(_ message: Binding<String?>) -> some View { modifier(ToastModifier(message: message)) }
}

/// A list row that acts as a button. The default style tints the whole label with the accent,
/// which turned titles and previews rust; this keeps label colors and dims the row while pressed.
struct RowButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(Color.primary, Color.secondary, Color(uiColor: .tertiaryLabel))
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(.rect)
            .opacity(configuration.isPressed ? 0.55 : 1)
    }
}

extension ButtonStyle where Self == RowButtonStyle {
    static var row: RowButtonStyle { RowButtonStyle() }
}
