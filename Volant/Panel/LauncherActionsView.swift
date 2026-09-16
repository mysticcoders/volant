import SwiftUI

/// Only everyday actions belong here; app termination and uninstall are deliberately separate work.
enum LauncherItemAction: String, CaseIterable, Identifiable {
    case open, reveal, contents, favorite, copyPath, copyName, copyBundleID, configure, resetRanking
    var id: String { rawValue }
    var title: String {
        switch self {
        case .open: return "Open"
        case .reveal: return "Reveal in Finder"
        case .contents: return "Show Package Contents"
        case .favorite: return "Add to Favorites"
        case .copyPath: return "Copy Path"
        case .copyName: return "Copy Name"
        case .copyBundleID: return "Copy Bundle Identifier"
        case .configure: return "Edit Shortcut & Alias…"
        case .resetRanking: return "Reset Ranking"
        }
    }
    var symbol: String {
        switch self {
        case .open: return "arrow.up.forward.app"
        case .reveal, .contents: return "folder"
        case .favorite: return "star"
        case .copyPath, .copyName, .copyBundleID: return "doc.on.clipboard"
        case .configure: return "gearshape"
        case .resetRanking: return "arrow.counterclockwise"
        }
    }
    var group: Int {
        switch self {
        case .open, .reveal, .contents: return 0
        case .favorite: return 1
        case .copyPath, .copyName, .copyBundleID: return 2
        case .configure, .resetRanking: return 3
        }
    }
}

extension ResultRow {
    var actionURL: URL? {
        switch self {
        case .app(let app): return app.url
        case .file(let file): return file.url
        default: return nil
        }
    }
    var supportsActions: Bool { actionURL != nil }
    var actionTitle: String {
        switch self {
        case .app(let app): return app.name
        case .file(let file): return file.name
        default: return ""
        }
    }
    var itemActions: [LauncherItemAction] {
        switch self {
        case .app: return LauncherItemAction.allCases
        case .file: return [.open, .reveal, .copyPath, .copyName, .resetRanking]
        default: return []
        }
    }
}

struct LauncherActionsView: View {
    @ObservedObject var model: LauncherModel
    let target: ResultRow
    let close: () -> Void
    @State private var query = ""
    @State private var selected: LauncherItemAction = .open
    @FocusState private var focused: Bool

    private func title(_ action: LauncherItemAction) -> String {
        if action == .open { return target.primaryAction }
        if action == .favorite, case .app(let app) = target, model.config.favoriteApps.contains(app.id) { return "Remove from Favorites" }
        return action.title
    }
    private var actions: [LauncherItemAction] {
        target.itemActions.filter { query.isEmpty || title($0).localizedCaseInsensitiveContains(query) }
    }
    private func move(_ delta: Int) {
        guard !actions.isEmpty else { return }
        guard let current = actions.firstIndex(of: selected) else { selected = actions[0]; return }
        selected = actions[max(0, min(actions.count - 1, current + delta))]
    }
    private func activate() {
        guard actions.contains(selected) else { return }
        model.performAction(selected, target: target)
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(target.actionTitle).font(.system(size: 12, weight: .medium)).foregroundStyle(.secondary)
                .lineLimit(1).padding(12)
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(spacing: 2) {
                        if actions.isEmpty { Text("No matching actions").foregroundStyle(.secondary).padding(16) }
                        ForEach(actions) { action in
                            if let index = actions.firstIndex(of: action), index > 0, actions[index - 1].group != action.group {
                                Divider().padding(.vertical, 5)
                            }
                            Button { model.performAction(action, target: target) } label: {
                                HStack(spacing: 10) {
                                    Image(systemName: action.symbol).frame(width: 20)
                                    Text(title(action)).lineLimit(1)
                                    Spacer(minLength: 4)
                                    if action == .open { KeyCap("↩") }
                                    if action == .reveal { KeyCap("⌘"); KeyCap("↩") }
                                }.font(.system(size: 13)).padding(.horizontal, 10).padding(.vertical, 9)
                                    .contentShape(Rectangle())
                                    .background(selected == action ? Color.primary.opacity(0.10) : .clear, in: RoundedRectangle(cornerRadius: 7))
                            }.buttonStyle(.plain).focusable(false).id(action)
                                .accessibilityIdentifier("launcher-action-" + action.rawValue)
                        }
                    }.padding(.horizontal, 8)
                }.frame(maxHeight: min(285, LauncherPanel.size.height - 150))
                .onChange(of: selected) { _, value in proxy.scrollTo(value) }
                .onChange(of: query) { _, _ in selected = actions.first ?? .open; proxy.scrollTo(selected) }
            }
            Divider().padding(.top, 8)
            TextField("Search for actions…", text: $query)
                .textFieldStyle(.plain).focused($focused).padding(12)
                .accessibilityIdentifier("launcher-action-search")
        }
        .frame(width: 330)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color.primary.opacity(0.15)))
        .shadow(color: .black.opacity(0.2), radius: 14, y: 4)
        .onAppear { focused = true }
        .onKeyPress(.downArrow) { move(1); return .handled }
        .onKeyPress(.upArrow) { move(-1); return .handled }
        .onKeyPress(.return, phases: .down) { press in
            if press.modifiers.contains(.command) { model.performAction(.reveal, target: target) } else { activate() }
            return .handled
        }
        .onKeyPress(.escape) { close(); return .handled }
    }
}
