import SwiftUI
import VolantCore

/// "Rex: 2 waiting" in the launcher footer. Like the Herdr status, it observes its own model so
/// Rex's five-second refreshes redraw this label and not the results list.
struct RexFooterStatus: View {
    @ObservedObject var rex: RexModel
    let onOpen: () -> Void
    let onHide: () -> Void
    @State private var hovering = false
    @Environment(\.volantTheme) private var theme
    @Environment(\.colorScheme) private var colorScheme

    /// The same readable orange as the Herdr status, so waiting reads alike in both.
    private var warning: Color {
        if let palette = theme.palette {
            return Color(hex: ColorPalette.readable(palette.orange, on: palette.background, toward: palette.text)) ?? .orange
        }
        let hex = colorScheme == .dark
            ? ColorPalette.readable("#ff9f0a", on: "#1e1e1e", toward: "#ffffff")
            : ColorPalette.readable("#ff9500", on: "#ececec", toward: "#000000")
        return Color(hex: hex) ?? .orange
    }

    var body: some View {
        let summary = RexStatusSummary(panes: rex.panes, connected: rex.connected, loading: rex.loading, problem: rex.problem)
        Button(action: onOpen) {
            HStack(spacing: 5) {
                Image(systemName: "terminal")
                Text(summary.text).lineLimit(1)
            }
            .font(.system(size: 12, weight: summary.waiting ? .medium : .regular))
            .foregroundStyle(summary.waiting ? AnyShapeStyle(warning) : AnyShapeStyle(.secondary))
            .padding(.horizontal, 6)
            .frame(height: 24)
            .background(hovering ? AnyShapeStyle(.tint.opacity(0.12)) : AnyShapeStyle(Color.clear), in: RoundedRectangle(cornerRadius: 5))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .focusable(false)
        .onHover { hovering = $0 }
        .help(summary.help)
        .accessibilityLabel(summary.text)
        .accessibilityHint("Shows Rex panes")
        .accessibilityIdentifier("launcher-rex-status")
        .contextMenu {
            Button("Hide Rex status", action: onHide)
        }
    }
}
