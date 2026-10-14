import AppKit
import SwiftUI

/// Grouped-form footers default to trailing, primary text on macOS 15; explanatory copy reads as
/// a leading caption under its section instead.
struct SettingsFooter: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View {
        Text(text).font(.callout).foregroundStyle(.secondary)
            .multilineTextAlignment(.leading)
            .frame(maxWidth: .infinity, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)
    }
}

/// An empty AppKit view behind a SwiftUI control, so native fixtures can find the control's frame
/// by identifier. SwiftUI builds its accessibility tree only for an assistive client, and form
/// buttons have no NSButton to search for.
struct ControlAnchor: NSViewRepresentable {
    let identifier: String
    init(_ identifier: String) { self.identifier = identifier }
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        view.identifier = NSUserInterfaceItemIdentifier(identifier)
        view.setAccessibilityElement(false)
        return view
    }
    func updateNSView(_ nsView: NSView, context: Context) {}
}

/// The translucent sidebar material behind Settings' section list, reaching under the titlebar so the
/// traffic lights sit on it.
struct SidebarMaterial: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .sidebar
        view.blendingMode = .behindWindow
        view.state = .followsWindowActiveState
        return view
    }
    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}

extension FormStyle where Self == SettingsFormStyle {
    /// Settings' card layout: rounded cards with no row separators, roomy rows and the theme's colors.
    static var settings: SettingsFormStyle { SettingsFormStyle() }
}

/// Lays a form's sections out as rounded cards. A native grouped form draws separators between rows
/// and ignores `listRowSeparator` on macOS, so rows are placed here, with switches and labeled rows
/// styled to keep the grouped form's label-left, control-right layout.
struct SettingsFormStyle: FormStyle {
    func makeBody(configuration: Configuration) -> some View {
        SettingsFormBody(content: configuration.content)
    }
}

private struct SettingsFormBody<Content: View>: View {
    let content: Content
    @Environment(\.volantTheme) private var theme

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                ForEach(sections: content) { section in
                    VStack(alignment: .leading, spacing: 8) {
                        if !section.header.isEmpty {
                            HStack { section.header }
                                .font(.system(size: 13, weight: .semibold))
                                .padding(.horizontal, 16)
                        }
                        if !section.content.isEmpty {
                            VStack(alignment: .leading, spacing: 0) {
                                ForEach(section.content) { row in
                                    row.frame(maxWidth: .infinity, alignment: .leading)
                                        .padding(.horizontal, 16)
                                        .padding(.vertical, 11)
                                }
                            }
                            .background(theme.settingsCard, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        }
                        if !section.footer.isEmpty {
                            VStack(alignment: .leading, spacing: 4) { section.footer }
                                .padding(.horizontal, 16)
                        }
                    }
                }
            }
            .padding(.horizontal, 24)
            .padding(.top, 4)
            .padding(.bottom, 24)
        }
        .toggleStyle(SettingsToggleStyle())
        .labeledContentStyle(SettingsLabeledContentStyle())
    }
}

/// A row's label: its first view as the title, any further views as secondary subtitle lines.
struct SettingsLabel<Label: View>: View {
    let label: Label
    var body: some View {
        Group(subviews: label) { subviews in
            VStack(alignment: .leading, spacing: 3) {
                if let title = subviews.first { title }
                ForEach(subviews.dropFirst()) { $0.font(.callout).foregroundStyle(.secondary) }
            }
            .fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// A switch on the trailing edge of its row, with the label and its subtitle on the leading edge.
struct SettingsToggleStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(alignment: .center, spacing: 16) {
            SettingsLabel(label: configuration.label)
            Spacer(minLength: 0)
            Toggle("", isOn: configuration.$isOn).toggleStyle(.switch).labelsHidden()
        }
        .accessibilityElement(children: .combine)
    }
}

/// A label on the leading edge and its value or controls on the trailing edge.
struct SettingsLabeledContentStyle: LabeledContentStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(alignment: .center, spacing: 16) {
            SettingsLabel(label: configuration.label)
            Spacer(minLength: 0)
            HStack(spacing: 8) { configuration.content }
        }
    }
}

extension ResolvedTheme {
    /// Settings cards: the palette's raised layer, or a light wash over the window background.
    var settingsCard: Color {
        palette.flatMap { Color(hex: $0.secondaryBackground) } ?? Color.primary.opacity(0.055)
    }
}

/// A rounded search field without a bezel, used by the sidebar and App Shortcuts.
struct SettingsSearchField: View {
    let prompt: String
    @Binding var text: String
    var submit: () -> Void = {}

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary).accessibilityHidden(true)
            TextField(prompt, text: $text)
                .textFieldStyle(.plain)
                .onSubmit(submit)
            if !text.isEmpty {
                Button { text = "" } label: { Image(systemName: "xmark.circle.fill") }
                    .buttonStyle(.plain).foregroundStyle(.secondary).help("Clear search")
            }
        }
        .padding(.horizontal, 8).padding(.vertical, 6)
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.primary.opacity(0.06)))
    }
}
