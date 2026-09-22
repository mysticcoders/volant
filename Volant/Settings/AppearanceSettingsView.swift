import SwiftUI
import VolantCore

/// Theme, launcher size and launcher opacity. Sliders keep a local draft while dragging and write
/// once on release, so a drag does not reload configuration and re-register hotkeys on every step.
struct AppearanceSettingsView: View {
    let appearance: Appearance
    let configURL: URL
    let onChange: () -> Void
    @State private var scale = 1.0
    @State private var opacity = 1.0
    @State private var error: String?

    var body: some View {
        Form {
            Section {
                HStack(spacing: 18) {
                    ForEach(Appearance.Theme.allCases) { theme in
                        ThemeTile(theme: theme, selected: appearance.theme == theme) {
                            save { $0.theme = theme }
                        }
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 4)
            } header: {
                Text("Theme")
            } footer: {
                SettingsFooter("System follows macOS, including automatic switching at sunset. Light and Dark keep Volant’s launcher, notes and Settings in that appearance.")
            }
            Section {
                Slider(value: $scale, in: Appearance.scaleRange, step: 0.05) {
                    Text("Size")
                } minimumValueLabel: {
                    Image(systemName: "textformat.size.smaller").accessibilityLabel("Smaller")
                } maximumValueLabel: {
                    Image(systemName: "textformat.size.larger").accessibilityLabel("Larger")
                } onEditingChanged: { editing in
                    if !editing { save { $0.scale = scale } }
                }
                LabeledContent("Current size", value: "\(Int((scale * 100).rounded()))%")
                Slider(value: $opacity, in: Appearance.opacityRange, step: 0.05) {
                    Text("Opacity")
                } minimumValueLabel: {
                    Image(systemName: "circle.dotted").accessibilityLabel("More transparent")
                } maximumValueLabel: {
                    Image(systemName: "circle.fill").accessibilityLabel("Opaque")
                } onEditingChanged: { editing in
                    if !editing { save { $0.opacity = opacity } }
                }
                LabeledContent("Current opacity", value: "\(Int((opacity * 100).rounded()))%")
                if appearance.clampedScale != 1 || appearance.clampedOpacity != 1 {
                    LabeledContent("Launcher") {
                        Button("Restore Defaults") { save { $0.scale = 1; $0.opacity = 1 } }
                    }
                }
            } header: {
                Text("Launcher")
            } footer: {
                SettingsFooter("Changes apply when you let go of a slider. Lower opacity lets more of the desktop show through the launcher.")
            }
        }
        .formStyle(.grouped)
        .onAppear(perform: adopt)
        .onChange(of: appearance) { _, _ in adopt() }
        .alert("Couldn’t change appearance", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
            Button("OK") { error = nil }
        } message: { Text(error ?? "") }
    }

    private func adopt() {
        scale = appearance.clampedScale
        opacity = appearance.clampedOpacity
    }

    private func save(_ change: (inout Appearance) -> Void) {
        var updated = appearance
        change(&updated)
        guard updated != appearance else { return }
        do {
            try Preferences.updateAppearance(updated, expected: appearance, at: configURL)
            onChange()
        } catch {
            self.error = error.localizedDescription
            adopt()
        }
    }
}

/// A miniature window in each appearance, split diagonally for System, like the macOS picker.
private struct ThemeTile: View {
    let theme: Appearance.Theme
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                preview
                    .frame(width: 88, height: 58)
                    .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .strokeBorder(selected ? Color.accentColor : Color.primary.opacity(0.15), lineWidth: selected ? 3 : 1)
                    }
                Text(theme.title).font(.callout).foregroundStyle(selected ? .primary : .secondary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(theme.title + " appearance")
        .accessibilityAddTraits(selected ? .isSelected : [])
        .background(ControlAnchor("settings.theme-" + theme.rawValue))
    }

    @ViewBuilder private var preview: some View {
        switch theme {
        case .light: WindowSketch(dark: false)
        case .dark: WindowSketch(dark: true)
        case .system:
            ZStack {
                WindowSketch(dark: false)
                WindowSketch(dark: true).mask {
                    GeometryReader { geometry in
                        Path { path in
                            path.move(to: CGPoint(x: geometry.size.width, y: 0))
                            path.addLine(to: CGPoint(x: geometry.size.width, y: geometry.size.height))
                            path.addLine(to: CGPoint(x: 0, y: geometry.size.height))
                            path.closeSubpath()
                        }
                    }
                }
            }
        }
    }
}

/// Fixed colors rather than semantic ones: each tile shows its own appearance whatever the
/// current one is.
private struct WindowSketch: View {
    let dark: Bool

    var body: some View {
        ZStack(alignment: .topLeading) {
            (dark ? Color(white: 0.16) : Color(white: 0.93))
            VStack(alignment: .leading, spacing: 5) {
                RoundedRectangle(cornerRadius: 3).fill(dark ? Color(white: 0.3) : .white).frame(height: 10)
                RoundedRectangle(cornerRadius: 2).fill(Color.accentColor).frame(width: 34, height: 6)
                RoundedRectangle(cornerRadius: 2).fill(dark ? Color(white: 0.34) : Color(white: 0.8)).frame(width: 48, height: 6)
                RoundedRectangle(cornerRadius: 2).fill(dark ? Color(white: 0.34) : Color(white: 0.8)).frame(width: 40, height: 6)
            }
            .padding(8)
        }
    }
}
