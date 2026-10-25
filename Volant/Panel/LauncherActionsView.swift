import SwiftUI
import VolantCore

/// Only everyday actions belong here; app termination and uninstall are deliberately separate work.
enum LauncherItemAction: String, CaseIterable, Identifiable {
    case open, reveal, contents, favorite, copyPath, copyName, copyBundleID, copyURL, copyPort, copyPID, configure, resetRanking
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
        case .copyURL: return "Copy URL"
        case .copyPort: return "Copy Port"
        case .copyPID: return "Copy Process ID"
        case .configure: return "Edit Shortcut & Alias…"
        case .resetRanking: return "Reset Ranking"
        }
    }
    var symbol: String {
        switch self {
        case .open: return "arrow.up.forward.app"
        case .reveal, .contents: return "folder"
        case .favorite: return "star"
        case .copyPath, .copyName, .copyBundleID, .copyURL, .copyPort, .copyPID: return "doc.on.clipboard"
        case .configure: return "gearshape"
        case .resetRanking: return "arrow.counterclockwise"
        }
    }
    var group: Int {
        switch self {
        case .open, .reveal, .contents: return 0
        case .favorite: return 1
        case .copyPath, .copyName, .copyBundleID, .copyURL, .copyPort, .copyPID: return 2
        case .configure, .resetRanking: return 3
        }
    }
}

/// One entry in the Actions menu: a built-in action, or an action a list extension's row offers.
enum LauncherMenuEntry: Hashable, Identifiable {
    case item(LauncherItemAction)
    case custom(ExtensionItemAction)
    var id: String {
        switch self {
        case .item(let action): return action.rawValue
        case .custom(let action): return "extension-" + action.id
        }
    }
    var symbol: String {
        switch self {
        case .item(let action): return action.symbol
        case .custom: return "puzzlepiece.extension"
        }
    }
    var group: Int {
        switch self {
        case .item(let action): return action.group
        case .custom: return 1
        }
    }
}

extension ResultRow {
    var actionURL: URL? {
        switch self {
        case .app(let app): return app.url
        case .file(let file): return file.url
        case .server(let server): return server.url
        default: return nil
        }
    }
    var supportsActions: Bool {
        if case .extensionItem(let item, _) = self { return !(item.actions ?? []).isEmpty || item.url != nil || item.secondaryURL != nil }
        return actionURL != nil
    }
    var actionTitle: String {
        switch self {
        case .app(let app): return app.name
        case .file(let file): return file.name
        case .server(let server): return "localhost:\(server.port)"
        case .extensionItem(let item, _): return item.title
        default: return ""
        }
    }
    /// What the Actions menu lists for this row: built-in actions, then an extension row's own.
    var menuEntries: [LauncherMenuEntry] {
        if case .extensionItem(let item, _) = self {
            let links: [LauncherMenuEntry] = (item.secondaryURL == nil ? [] : [.item(.reveal)]) + (item.url == nil ? [] : [.item(.copyPath)])
            return [.item(.open)] + links + (item.actions ?? []).map { .custom($0) }
        }
        return itemActions.map { .item($0) }
    }
    /// The menu entry Command-Return runs, the same action Command-Return runs from the results.
    var commandReturnEntry: LauncherMenuEntry {
        if case .server = self { return .item(.copyURL) }
        return .item(.reveal)
    }
    var itemActions: [LauncherItemAction] {
        switch self {
        case .app: return [.open, .reveal, .contents, .favorite, .copyPath, .copyName, .copyBundleID, .configure, .resetRanking]
        case .file: return [.open, .reveal, .copyPath, .copyName, .resetRanking]
        case .server(let server): return [.open] + (server.executable == nil ? [] : [.reveal]) + [.copyURL, .copyPort, .copyPID]
        default: return []
        }
    }
}

struct LauncherActionsView: View {
    @ObservedObject var model: LauncherModel
    let target: ResultRow
    let close: () -> Void
    @State private var query = ""
    @State private var selected: LauncherMenuEntry = .item(.open)
    @FocusState private var focused: Bool
    @Environment(\.volantTheme) private var theme

    private func title(_ entry: LauncherMenuEntry) -> String {
        guard case .item(let action) = entry else { if case .custom(let custom) = entry { return custom.title }; return "" }
        if action == .open { return target.primaryAction }
        if case .extensionItem = target {
            if action == .reveal { return target.secondaryAction ?? action.title }
            if action == .copyPath { return "Copy Link" }
        }
        if action == .favorite, case .app(let app) = target, model.config.favoriteApps.contains(app.id) { return "Remove from Favorites" }
        return action.title
    }
    /// An extension row's built-in entries are about links, not files, so they get link symbols.
    private func symbol(_ entry: LauncherMenuEntry) -> String {
        guard case .extensionItem = target, case .item(let action) = entry else { return entry.symbol }
        switch action {
        case .open: return "arrow.up.right.square"
        case .reveal: return "bubble.left.and.bubble.right"
        case .copyPath: return "link"
        default: return entry.symbol
        }
    }
    private var actions: [LauncherMenuEntry] {
        target.menuEntries.filter { query.isEmpty || title($0).localizedCaseInsensitiveContains(query) }
    }
    private func move(_ delta: Int) {
        guard !actions.isEmpty else { return }
        guard let current = actions.firstIndex(of: selected) else { selected = actions[0]; return }
        selected = actions[max(0, min(actions.count - 1, current + delta))]
    }
    private func activate() {
        guard actions.contains(selected) else { return }
        model.performMenuEntry(selected, target: target)
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
                            Button { model.performMenuEntry(action, target: target) } label: {
                                HStack(spacing: 10) {
                                    Image(systemName: symbol(action)).frame(width: 20)
                                    Text(title(action)).lineLimit(1)
                                    Spacer(minLength: 4)
                                    if action == .item(.open) { KeyCap("↩") }
                                    if action == target.commandReturnEntry { KeyCap("⌘"); KeyCap("↩") }
                                }.font(.system(size: 13)).padding(.horizontal, 10).padding(.vertical, 9)
                                    .contentShape(Rectangle())
                                    .background(selected == action ? theme.selection : AnyShapeStyle(Color.clear), in: RoundedRectangle(cornerRadius: 7))
                            }.buttonStyle(.plain).focusable(false).id(action)
                                .accessibilityIdentifier("launcher-action-" + action.id)
                        }
                    }.padding(.horizontal, 8)
                }.frame(maxHeight: min(285, LauncherPanel.size.height - 150))
                .onChange(of: selected) { _, value in proxy.scrollTo(value) }
                .onChange(of: query) { _, _ in selected = actions.first ?? .item(.open); proxy.scrollTo(selected) }
            }
            Divider().padding(.top, 8)
            TextField("Search for actions…", text: $query)
                .textFieldStyle(.plain).focused($focused).padding(12)
                .accessibilityIdentifier("launcher-action-search")
        }
        .frame(width: 330)
        .background(theme.raisedSurface, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(theme.separator(0.15)))
        .shadow(color: .black.opacity(0.2), radius: 14, y: 4)
        .onAppear { focused = true }
        .onKeyPress(.downArrow) { move(1); return .handled }
        .onKeyPress(.upArrow) { move(-1); return .handled }
        .onKeyPress(.return, phases: .down) { press in
            if press.modifiers.contains(.command) { model.performMenuEntry(target.commandReturnEntry, target: target) } else { activate() }
            return .handled
        }
        .onKeyPress(.escape) { close(); return .handled }
    }
}
