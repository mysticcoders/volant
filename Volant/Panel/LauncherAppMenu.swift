import SwiftUI

/// The launcher's own menu, opened from the Volant mark at the bottom left of the footer.
enum LauncherMenuItem: String, CaseIterable, Identifiable {
    case feedback, manual, changelog, updates, about, settings, quit
    var id: String { rawValue }
    var title: String {
        switch self {
        case .feedback: return "Send Feedback"
        case .manual: return "Manual"
        case .changelog: return "Changelog"
        case .updates: return "Check for Updates…"
        case .about: return "About Volant"
        case .settings: return "Settings"
        case .quit: return "Quit Volant"
        }
    }
    var symbol: String {
        switch self {
        case .feedback: return "bubble.left"
        case .manual: return "questionmark.circle"
        case .changelog: return "doc.text"
        case .updates: return "arrow.down.circle"
        case .about: return "info.circle"
        case .settings: return "gearshape"
        case .quit: return "power"
        }
    }
    var keys: [String] {
        switch self {
        case .settings: return ["⌘", ","]
        case .quit: return ["⌘", "Q"]
        default: return []
        }
    }
    var group: Int {
        switch self {
        case .feedback, .manual, .changelog, .updates: return 0
        case .about, .settings, .quit: return 1
        }
    }

    static let manualURL = URL(string: "https://usevolant.com/docs")!
    static let changelogURL = URL(string: "https://github.com/mysticcoders/volant/releases")!

    /// Items whose title contains the search text, in menu order.
    static func matching(_ query: String) -> [LauncherMenuItem] {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        return allCases.filter { trimmed.isEmpty || $0.title.localizedCaseInsensitiveContains(trimmed) }
    }

    /// The menu header, such as "Volant v0.2.1", from the running bundle's version.
    static func versionTitle(bundle: Bundle = .main) -> String {
        let version = bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        return version.map { "Volant v" + $0 } ?? "Volant"
    }

    /// A new GitHub issue with the app version, build and macOS version filled in, and nothing personal.
    static func feedbackURL(bundle: Bundle = .main, system: OperatingSystemVersion = ProcessInfo.processInfo.operatingSystemVersion) -> URL {
        let version = bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "unknown"
        let build = bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "unknown"
        let macOS = "\(system.majorVersion).\(system.minorVersion).\(system.patchVersion)"
        var components = URLComponents(string: "https://github.com/mysticcoders/volant/issues/new")!
        components.queryItems = [URLQueryItem(name: "body", value: "\n\n---\nVolant \(version) (build \(build)), macOS \(macOS)")]
        return components.url!
    }
}

struct LauncherAppMenuView: View {
    @ObservedObject var model: LauncherModel
    let close: () -> Void
    @State private var query = ""
    @State private var selected: LauncherMenuItem = .feedback
    @FocusState private var focused: Bool
    @Environment(\.volantTheme) private var theme

    private var items: [LauncherMenuItem] { LauncherMenuItem.matching(query) }

    private func move(_ delta: Int) {
        guard !items.isEmpty else { return }
        guard let current = items.firstIndex(of: selected) else { selected = items[0]; return }
        selected = items[max(0, min(items.count - 1, current + delta))]
    }

    private func activate() {
        guard items.contains(selected) else { return }
        model.performMenuItem(selected)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(LauncherMenuItem.versionTitle()).font(.system(size: 12, weight: .medium)).foregroundStyle(.secondary)
                .lineLimit(1).padding(12).accessibilityIdentifier("launcher-app-menu-version")
            VStack(spacing: 2) {
                if items.isEmpty { Text("No matching actions").foregroundStyle(.secondary).padding(16) }
                ForEach(items) { item in
                    if let index = items.firstIndex(of: item), index > 0, items[index - 1].group != item.group {
                        Divider().padding(.vertical, 5)
                    }
                    row(item)
                }
            }.padding(.horizontal, 8)
            Divider().padding(.top, 8)
            TextField("Search for actions…", text: $query)
                .textFieldStyle(.plain).focused($focused).padding(12)
                .accessibilityIdentifier("launcher-app-menu-search")
        }
        .frame(width: 300)
        .background(theme.raisedSurface, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(theme.separator(0.15)))
        .shadow(color: .black.opacity(0.2), radius: 14, y: 4)
        .onAppear { focused = true }
        .onChange(of: query) { _, _ in selected = items.first ?? .feedback }
        .onKeyPress(.downArrow) { move(1); return .handled }
        .onKeyPress(.upArrow) { move(-1); return .handled }
        .onKeyPress(.return, phases: .down) { _ in activate(); return .handled }
        .onKeyPress(.escape) { close(); return .handled }
    }

    /// One native button per item, highlighted when it is the keyboard selection.
    private func row(_ item: LauncherMenuItem) -> some View {
        Button { model.performMenuItem(item) } label: {
            HStack(spacing: 10) {
                icon(item).frame(width: 20)
                Text(item.title).lineLimit(1)
                Spacer(minLength: 4)
                ForEach(item.keys, id: \.self) { KeyCap($0) }
            }.font(.system(size: 13)).padding(.horizontal, 10).padding(.vertical, 8)
                .contentShape(Rectangle())
                .background(selected == item ? theme.selection : AnyShapeStyle(Color.clear), in: RoundedRectangle(cornerRadius: 7))
        }.buttonStyle(.plain).focusable(false)
            .accessibilityIdentifier("launcher-app-menu-" + item.rawValue)
    }

    /// The Volant mark for About, matching the footer button; SF Symbols for everything else.
    @ViewBuilder private func icon(_ item: LauncherMenuItem) -> some View {
        if item == .about {
            Image("VolantWing").renderingMode(.template).resizable().scaledToFit().frame(width: 15, height: 15).foregroundStyle(.tint)
        } else {
            Image(systemName: item.symbol)
        }
    }
}
