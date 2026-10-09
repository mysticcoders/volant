import SwiftUI
import VolantCore

/// "Herdr: 3 waiting" in the launcher footer, beside Caffeinate. It is the only launcher element
/// outside the `herdr` view that observes the agents model, so Herdr's five-second refreshes
/// redraw this label and not the results list.
struct HerdrFooterStatus: View {
    @ObservedObject var agents: AgentsModel
    /// The harness the owner chose in Settings, or `all` for every Herdr agent.
    let filter: String
    let onOpen: () -> Void
    let onConfigure: (String?) -> Void
    @State private var hovering = false
    @Environment(\.volantTheme) private var theme
    @Environment(\.colorScheme) private var colorScheme

    private var sessions: [AgentSession] { agents.sessions.filter { filter == "all" || $0.agent == filter } }

    /// The theme's orange, or the system orange, darkened just enough for 12-point text to reach
    /// WCAG AA on the footer. Plain system orange is about 2:1 on a light window background.
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
        let shown = sessions
        let summary = HerdrStatusSummary(sessions: shown, connected: agents.connected, busy: agents.busy,
                                         machines: agents.machines, unread: shown.filter(agents.isUnread).count)
        let scope = filter == "all" ? "" : (Preferences.harnessOptions.first { $0.id == filter }?.title ?? filter) + " only. "
        Button(action: onOpen) {
            HStack(spacing: 5) {
                Image(systemName: summary.tone == .warning ? "exclamationmark.triangle" : "waveform.path")
                Text(summary.text).lineLimit(1)
            }
            .font(.system(size: 12, weight: summary.tone == .waiting ? .medium : .regular))
            .foregroundStyle(summary.tone == .quiet ? AnyShapeStyle(.secondary) : AnyShapeStyle(warning))
            .padding(.horizontal, 6)
            .frame(height: 24)
            .background(hovering ? AnyShapeStyle(.tint.opacity(0.12)) : AnyShapeStyle(Color.clear), in: RoundedRectangle(cornerRadius: 5))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .focusable(false)
        .onHover { hovering = $0 }
        .help(scope + summary.help)
        .accessibilityLabel(summary.text)
        .accessibilityHint("Shows Herdr panes")
        .accessibilityIdentifier("launcher-herdr-status")
        .contextMenu {
            Button("Hide Herdr status") { onConfigure(nil) }
            Divider()
            ForEach(Preferences.harnessOptions, id: \.id) { option in
                Button(option.title) { onConfigure(option.id) }
            }
        }
    }
}
