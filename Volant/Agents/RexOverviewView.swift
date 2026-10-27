import SwiftUI
import VolantCore

/// Every Rex session as a grid of tab cards. Each card draws its tab's panes where they sit in Rex,
/// colored by what their programs last reported, with the last lines of each pane's screen; clicking
/// a pane, or pressing Return on the selected one, focuses it in Rex. The window's keys move the
/// selection (`RexOverviewWindow`), and the selected card is kept in view. Until the owner turns on
/// pane previews, the window asks for that instead.
struct RexOverviewView: View {
    @ObservedObject var model: RexOverviewModel
    let close: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            if !model.previewsAllowed {
                RexPreviewConsent(allow: { model.allowPreviews(true) }, notNow: close)
            } else if let message = model.message {
                Text(message).foregroundStyle(.secondary).frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 24) {
                            ForEach(model.overview.sessions) { session in
                                RexSessionSection(session: session, selectedBlockID: selectedBlock(in: session),
                                                  minimized: model.isMinimized(session),
                                                  toggleMinimized: { model.toggleMinimized(session) }) { pane in
                                    model.select(.init(sessionID: session.sessionID, blockID: pane.blockID))
                                    model.focus(pane, in: session)
                                }
                            }
                        }
                        .padding(20)
                    }
                    .onChange(of: model.selection) { _, selection in
                        guard let selection, let place = model.overview.pane(selection) else { return }
                        let target = model.isMinimized(place.session) ? RexSessionSection.scrollID(place.session) : RexTabCard.scrollID(place.session, place.tab)
                        withAnimation(.easeOut(duration: 0.15)) { proxy.scrollTo(target) }
                    }
                }
            }
        }
        .frame(minWidth: 640, minHeight: 420)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private func selectedBlock(in session: RexOverview.Session) -> String? {
        model.selection.flatMap { $0.sessionID == session.sessionID ? $0.blockID : nil }
    }

    private var header: some View {
        let waiting = model.overview.sessions.reduce(0) { $0 + $1.waiting }
        return HStack(spacing: 12) {
            Text("Rex Overview").font(.system(size: 15, weight: .semibold))
            if waiting > 0 {
                Label("\(waiting) waiting", systemImage: "exclamationmark.bubble")
                    .font(.system(size: 12, weight: .medium)).foregroundStyle(.orange)
            }
            if let feedback = model.feedback {
                Text(feedback).font(.system(size: 12)).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer()
            if model.keyboardActive {
                Text("← → tabs   ↑ ↓ panes   ⇥ waiting   ␣ minimize session   ↩ focus")
                    .font(.system(size: 11)).foregroundStyle(.tertiary).lineLimit(1)
                    .accessibilityLabel("Arrow keys move between tabs and panes, Tab moves to the next waiting pane, Space minimizes or expands the session, Return focuses it in Rex")
            }
            if model.previewsAllowed {
                Button("Turn Off Pane Previews") { model.allowPreviews(false) }
                    .controlSize(.small)
                    .accessibilityIdentifier("rex-overview-previews-off")
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 14)
        .padding(.bottom, 12)
    }
}

/// What turning on previews reads, asked before the overview reads any screen.
struct RexPreviewConsent: View {
    let allow: () -> Void
    let notNow: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Show what’s on each pane’s screen?", systemImage: "eye").font(.system(size: 15, weight: .semibold))
            Text("The overview shows the last \(RexScript.previewLines) lines of every Rex pane’s screen on this Mac, refreshed every two seconds while this window is open. That can include commands, file contents or anything else a program printed.")
            Text("The text stays in memory while this window shows it. Volant never saves, logs or sends it anywhere, and stops reading screens when you close the window. You can change this later in Settings › Status Bar.")
                .foregroundStyle(.secondary)
            HStack {
                Button("Turn On Pane Previews", action: allow).keyboardShortcut(.defaultAction)
                Button("Not Now", action: notNow)
            }
            .padding(.top, 4)
        }
        .font(.system(size: 13))
        .frame(maxWidth: 520, alignment: .leading)
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityIdentifier("rex-preview-consent")
    }
}

/// One session: its name and waiting count, then its tabs as cards. A minimized session shows only
/// its heading and a pill per tab with a dot per pane, so a pane that starts waiting is still in
/// sight; it is outlined while it holds the keyboard selection.
struct RexSessionSection: View {
    let session: RexOverview.Session
    let selectedBlockID: String?
    let minimized: Bool
    let toggleMinimized: () -> Void
    let focus: (RexOverview.Pane) -> Void

    /// The section's scroll identity, used while it is minimized and has no cards to scroll to.
    static func scrollID(_ session: RexOverview.Session) -> String { "session|" + session.sessionID }

    private var holdsSelection: Bool { minimized && session.tabs.contains { $0.panes.contains { $0.blockID == selectedBlockID } } }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            heading
            if minimized {
                tabPills
            } else {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 260), spacing: 14, alignment: .top)], alignment: .leading, spacing: 14) {
                    ForEach(session.tabs) { tab in
                        RexTabCard(tab: tab, selectedBlockID: selectedBlockID, focus: focus)
                            .id(RexTabCard.scrollID(session, tab))
                    }
                }
            }
        }
        .padding(minimized ? 8 : 0)
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous)
            .strokeBorder(holdsSelection ? AnyShapeStyle(.tint) : AnyShapeStyle(Color.clear), lineWidth: 2))
        .id(Self.scrollID(session))
    }

    private var heading: some View {
        HStack(spacing: 8) {
            Button(action: toggleMinimized) {
                Image(systemName: minimized ? "chevron.right" : "chevron.down")
                    .font(.system(size: 10, weight: .semibold)).foregroundStyle(.secondary)
                    .frame(width: 14, height: 14).contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(minimized ? "Expand this session" : "Minimize this session")
            .accessibilityLabel(minimized ? String(localized: "Expand \(session.label)", comment: "Rex Overview: expand a minimized session") : String(localized: "Minimize \(session.label)", comment: "Rex Overview: minimize a session"))
            Text(session.label).font(.system(size: 13, weight: .semibold))
            Text("\(session.tabs.count) tabs", comment: "Rex Overview: number of tabs in a session; needs a plural variant for one tab").font(.system(size: 12)).foregroundStyle(.secondary)
            if session.waiting > 0 {
                Text("\(session.waiting) waiting").font(.system(size: 12, weight: .medium)).foregroundStyle(.orange)
            }
        }
    }

    /// A minimized session's tabs as pills: the tab's name and a dot per pane in reading order,
    /// the selected one ringed.
    private var tabPills: some View {
        HStack(spacing: 8) {
            ForEach(session.tabs) { tab in
                HStack(spacing: 4) {
                    Text(tab.name).font(.system(size: 11, weight: .medium)).lineLimit(1)
                    ForEach(RexOverview.readingOrder(tab.panes).prefix(8)) { pane in
                        Circle().fill(pane.state.overviewTint).frame(width: 7, height: 7)
                            .overlay(Circle().strokeBorder(pane.blockID == selectedBlockID ? Color.primary : Color.clear, lineWidth: 1.5).padding(-2))
                            .help(pane.name + ", " + pane.state.title)
                            .accessibilityLabel(pane.name + ", " + pane.state.title)
                    }
                    if tab.panes.count > 8 {
                        Text("+\(tab.panes.count - 8)").font(.system(size: 10)).foregroundStyle(.secondary)
                    }
                }
                .padding(.horizontal, 8).padding(.vertical, 3)
                .background(Color(nsColor: .controlBackgroundColor), in: Capsule())
                .overlay(Capsule().strokeBorder(tab.waiting > 0 ? AnyShapeStyle(Color.orange.opacity(0.7)) : AnyShapeStyle(.separator), lineWidth: 1))
            }
            Spacer(minLength: 0)
        }
        .lineLimit(1)
    }
}

/// One tab: its name, whether Rex shows it, and its panes drawn where they sit.
struct RexTabCard: View {
    let tab: RexOverview.Tab
    let selectedBlockID: String?
    let focus: (RexOverview.Pane) -> Void

    /// The card's scroll identity: its session and tab, since tab IDs belong to one session.
    static func scrollID(_ session: RexOverview.Session, _ tab: RexOverview.Tab) -> String { session.sessionID + "|" + tab.windowID }

    private var holdsSelection: Bool { tab.panes.contains { $0.blockID == selectedBlockID } }

    /// What Rex shows in the tab: the zoomed pane alone, or the tiled layout with floating layers
    /// drawn over it, back to front.
    private var drawnPanes: [RexOverview.Pane] {
        if let zoomed = tab.zoomedPane { return [zoomed] }
        return tab.panes.sorted { $0.layer < $1.layer }
    }

    private var hasFloating: Bool { tab.zoomedPane == nil && tab.panes.contains(where: \.floating) }

    /// A floating tile sits on an opaque base, so the tiles it covers never show through its tint.
    private func tile(_ pane: RexOverview.Pane) -> some View {
        RexPaneTile(pane: pane, focused: pane.blockID == tab.focusedBlockID, selected: pane.blockID == selectedBlockID) { focus(pane) }
            .background(pane.floating ? Color(nsColor: .controlBackgroundColor) : Color.clear, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
    }

    /// Places a view at a rect given as fractions of the tab, inset so neighbours keep a gap.
    private func place<Content: View>(_ content: Content, at rect: [Double], in size: CGSize) -> some View {
        content
            .frame(width: max(rect[2] * size.width - 4, 0), height: max(rect[3] * size.height - 4, 0))
            .offset(x: rect[0] * size.width + 2, y: rect[1] * size.height + 2)
    }

    private var border: AnyShapeStyle {
        if holdsSelection { return AnyShapeStyle(.tint) }
        return tab.waiting > 0 ? AnyShapeStyle(Color.orange.opacity(0.7)) : AnyShapeStyle(.separator)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            heading
            paneMap
            if !tab.hiddenPanes.isEmpty {
                RexHiddenPanes(panes: tab.hiddenPanes, selectedBlockID: selectedBlockID, focus: focus)
            }
        }
        .padding(10)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous)
            .strokeBorder(border, lineWidth: holdsSelection ? 2 : 1))
    }

    private var heading: some View {
        HStack(spacing: 6) {
            Circle().fill(tab.active ? AnyShapeStyle(.tint) : AnyShapeStyle(.quaternary)).frame(width: 6, height: 6)
                .accessibilityLabel(tab.active ? "Shown in Rex" : "")
            Text(tab.name).font(.system(size: 12, weight: .medium)).lineLimit(1)
            if tab.zoomedPane != nil {
                Label("Zoomed", systemImage: "arrow.up.left.and.arrow.down.right")
                    .font(.system(size: 10, weight: .medium)).foregroundStyle(.secondary)
                    .padding(.horizontal, 5).padding(.vertical, 1)
                    .background(.quaternary, in: Capsule())
            }
            Spacer(minLength: 4)
            if tab.waiting > 0 {
                Text("\(tab.waiting)").font(.system(size: 11, weight: .semibold)).foregroundStyle(.white)
                    .padding(.horizontal, 6).padding(.vertical, 1).background(.orange, in: Capsule())
                    .accessibilityLabel("\(tab.waiting) waiting")
            }
        }
    }

    private var paneMap: some View {
        GeometryReader { geometry in
            ZStack(alignment: .topLeading) {
                ForEach(drawnPanes) { pane in
                    place(tile(pane), at: tab.zoomedPane == nil ? (pane.rect ?? [0, 0, 1, 1]) : [0, 0, 1, 1], in: geometry.size)
                        .opacity(!pane.floating && hasFloating ? 0.75 : 1)
                        .shadow(color: .black.opacity(pane.floating ? 0.35 : 0), radius: pane.floating ? 6 : 0, y: pane.floating ? 2 : 0)
                }
            }
        }
        .aspectRatio(16 / 10, contentMode: .fit)
    }
}

/// The panes a zoom hides, as chips under the zoomed pane, so nothing waiting is out of sight.
/// Each chip is a native button that focuses its pane, like a tile.
struct RexHiddenPanes: View {
    let panes: [RexOverview.Pane]
    let selectedBlockID: String?
    let focus: (RexOverview.Pane) -> Void
    static let maximumChips = 3

    /// Up to three chips, waiting ones first; a selected pane beyond them takes the last place.
    private var shown: [RexOverview.Pane] {
        let ordered = panes.filter { $0.state == .blocked } + panes.filter { $0.state != .blocked }
        var chips = Array(ordered.prefix(Self.maximumChips))
        if let selected = panes.first(where: { $0.blockID == selectedBlockID }), !chips.contains(where: { $0.blockID == selected.blockID }) {
            chips[chips.count - 1] = selected
        }
        return chips
    }

    var body: some View {
        HStack(spacing: 6) {
            Text("Hidden").font(.system(size: 10)).foregroundStyle(.tertiary)
            ForEach(shown) { pane in
                Button { focus(pane) } label: { chip(pane) }
                    .buttonStyle(.plain)
                    .help(String(localized: "Focus \(pane.name) in Rex", comment: "Rex Overview tooltip on a pane"))
                    .accessibilityLabel(String(localized: "\(pane.name), hidden behind the zoomed pane, \(pane.state.title)", comment: "Rex Overview accessibility label: pane name, then its state"))
                    .accessibilityAddTraits(pane.blockID == selectedBlockID ? .isSelected : [])
            }
            if panes.count > shown.count {
                Text("+\(panes.count - shown.count)").font(.system(size: 10)).foregroundStyle(.secondary)
                    .accessibilityLabel("\(panes.count - shown.count) more hidden")
            }
            Spacer(minLength: 0)
        }
        .lineLimit(1)
    }

    private func chip(_ pane: RexOverview.Pane) -> some View {
        HStack(spacing: 4) {
            Circle().fill(pane.state.overviewTint).frame(width: 6, height: 6)
            Text(pane.program ?? pane.name).font(.system(size: 10, weight: .medium))
            Text(pane.state.title).font(.system(size: 10)).foregroundStyle(.secondary)
        }
        .padding(.horizontal, 6).padding(.vertical, 2)
        .background(pane.state.overviewTint.opacity(pane.state == .idle ? 0.06 : 0.14), in: Capsule())
        .overlay(Capsule().strokeBorder(pane.blockID == selectedBlockID ? Color.primary : Color.clear, lineWidth: 2))
    }
}

extension RexState {
    /// The overview's color for a state, shared by tiles and hidden-pane chips.
    var overviewTint: Color {
        switch self {
        case .blocked: return .orange
        case .error: return .red
        case .done: return .green
        case .working: return .accentColor
        case .idle: return .secondary
        }
    }
}

/// One pane, a native button that focuses it in Rex.
struct RexPaneTile: View {
    let pane: RexOverview.Pane
    let focused: Bool
    let selected: Bool
    let action: () -> Void

    private var tint: Color { pane.state.overviewTint }

    private var symbol: String {
        switch pane.state {
        case .blocked: return "exclamationmark.bubble"
        case .error: return "xmark.octagon"
        case .done: return "checkmark.circle"
        case .working, .idle: return "terminal"
        }
    }

    var body: some View {
        Button(action: action) { tile }
            .buttonStyle(.plain)
            .help(String(localized: "Focus \(pane.name) in Rex", comment: "Rex Overview tooltip on a pane"))
            .accessibilityLabel(accessibilityText)
            .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private var accessibilityText: String {
        pane.name + ", " + pane.state.title + (pane.status?.message.map { ", " + $0 } ?? "")
    }

    private var tile: some View {
        VStack(alignment: .leading, spacing: 4) {
            heading
            content
        }
        .padding(6)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(tint.opacity(pane.state == .idle ? 0.06 : 0.14), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
        .overlay(outline)
        .contentShape(Rectangle())
    }

    /// The full heading where it fits; a narrower tile drops the state, then truncates the name.
    private var heading: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 4) {
                Image(systemName: symbol).foregroundStyle(tint)
                Text(pane.program ?? pane.name).lineLimit(1).fixedSize()
                Spacer(minLength: 2)
                Text(pane.state.title).foregroundStyle(.secondary).lineLimit(1).fixedSize()
            }
            HStack(spacing: 4) {
                Image(systemName: symbol).foregroundStyle(tint)
                Text(pane.program ?? pane.name).lineLimit(1).fixedSize()
                Spacer(minLength: 0)
            }
            HStack(spacing: 4) {
                Image(systemName: symbol).foregroundStyle(tint)
                Text(pane.program ?? pane.name).lineLimit(1).truncationMode(.tail)
                Spacer(minLength: 0)
            }
        }
        .font(.system(size: 10, weight: .medium))
    }

    /// The screen's last lines, each cut at the tile's edge as a terminal would, with the newest at
    /// the bottom; the status message stands in until the first preview arrives.
    @ViewBuilder private var content: some View {
        if let lines = pane.preview {
            VStack(alignment: .leading, spacing: 1) {
                ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                    Text(line.isEmpty ? " " : line).lineLimit(1).truncationMode(.tail)
                }
            }
            .font(.system(size: 8, design: .monospaced))
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
            .clipped()
        } else {
            Text(pane.status?.message ?? pane.title ?? pane.name)
                .font(.system(size: 11))
                .lineLimit(4)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }

    /// The keyboard selection outranks the pane Rex focuses in the tab, and is drawn in the primary
    /// text color so it never reads as a status: working panes are already tinted with the accent.
    private var outline: some View {
        RoundedRectangle(cornerRadius: 6, style: .continuous)
            .strokeBorder(selected ? Color.primary : (focused ? tint.opacity(0.8) : Color.clear), lineWidth: selected ? 2 : 1)
    }
}
