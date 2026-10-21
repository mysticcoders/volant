import SwiftUI
import VolantCore

/// Every Rex session as a grid of tab cards. Each card draws its tab's panes where they sit in Rex,
/// colored by what their programs last reported; clicking a pane focuses it in Rex. Status mode
/// shows each pane's program and message; Preview mode, once the owner turns it on, shows the last
/// lines of its screen instead.
struct RexOverviewView: View {
    @ObservedObject var model: RexOverviewModel

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            if model.mode == .preview && !model.previewsAllowed {
                RexPreviewConsent(allow: { model.allowPreviews(true) }, back: { model.mode = .status })
            } else if let message = model.message {
                Text(message).foregroundStyle(.secondary).frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 24) {
                        ForEach(model.overview.sessions) { session in
                            RexSessionSection(session: session, mode: model.readsPreviews ? .preview : .status) { model.focus($0, in: session) }
                        }
                    }
                    .padding(20)
                }
            }
        }
        .frame(minWidth: 640, minHeight: 420)
        .background(Color(nsColor: .windowBackgroundColor))
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
            if model.readsPreviews {
                Button("Turn Off Previews") { model.allowPreviews(false); model.mode = .status }
                    .controlSize(.small)
            }
            Picker("View", selection: $model.mode) {
                Text("Status").tag(RexOverviewModel.Mode.status)
                Text("Preview").tag(RexOverviewModel.Mode.preview)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 180)
            .accessibilityIdentifier("rex-overview-mode")
        }
        .padding(.horizontal, 20)
        .padding(.top, 14)
        .padding(.bottom, 12)
    }
}

/// What turning on previews reads, asked before the first preview.
struct RexPreviewConsent: View {
    let allow: () -> Void
    let back: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Show what’s on each pane’s screen?", systemImage: "eye").font(.system(size: 15, weight: .semibold))
            Text("Previews read the text on every Rex pane’s screen on this Mac and show its last \(RexScript.previewLines) lines here, refreshed every two seconds while Preview is showing. That can include commands, file contents or anything else a program printed.")
            Text("The text stays in memory while this window shows it. Volant never saves, logs or sends it anywhere, and stops reading screens when you switch back to Status or close the window.")
                .foregroundStyle(.secondary)
            HStack {
                Button("Turn On Pane Previews", action: allow).keyboardShortcut(.defaultAction)
                Button("Not Now", action: back)
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

/// One session: its name and waiting count, then its tabs as cards.
struct RexSessionSection: View {
    let session: RexOverview.Session
    let mode: RexOverviewModel.Mode
    let focus: (RexOverview.Pane) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Text(session.label).font(.system(size: 13, weight: .semibold))
                Text("\(session.tabs.count) \(session.tabs.count == 1 ? "tab" : "tabs")").font(.system(size: 12)).foregroundStyle(.secondary)
                if session.waiting > 0 {
                    Text("\(session.waiting) waiting").font(.system(size: 12, weight: .medium)).foregroundStyle(.orange)
                }
            }
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 260), spacing: 14)], alignment: .leading, spacing: 14) {
                ForEach(session.tabs) { tab in RexTabCard(tab: tab, mode: mode, focus: focus) }
            }
        }
    }
}

/// One tab: its name, whether Rex shows it, and its panes drawn where they sit.
struct RexTabCard: View {
    let tab: RexOverview.Tab
    let mode: RexOverviewModel.Mode
    let focus: (RexOverview.Pane) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Circle().fill(tab.active ? AnyShapeStyle(.tint) : AnyShapeStyle(.quaternary)).frame(width: 6, height: 6)
                    .accessibilityLabel(tab.active ? "Shown in Rex" : "")
                Text(tab.name).font(.system(size: 12, weight: .medium)).lineLimit(1)
                Spacer(minLength: 4)
                if tab.waiting > 0 {
                    Text("\(tab.waiting)").font(.system(size: 11, weight: .semibold)).foregroundStyle(.white)
                        .padding(.horizontal, 6).padding(.vertical, 1).background(.orange, in: Capsule())
                        .accessibilityLabel("\(tab.waiting) waiting")
                }
            }
            GeometryReader { geometry in
                ZStack(alignment: .topLeading) {
                    ForEach(tab.panes) { pane in
                        let rect = pane.rect ?? [0, 0, 1, 1]
                        RexPaneTile(pane: pane, mode: mode, focused: pane.blockID == tab.focusedBlockID) { focus(pane) }
                            .frame(width: max(rect[2] * geometry.size.width - 4, 0), height: max(rect[3] * geometry.size.height - 4, 0))
                            .offset(x: rect[0] * geometry.size.width + 2, y: rect[1] * geometry.size.height + 2)
                    }
                }
            }
            .aspectRatio(16 / 10, contentMode: .fit)
        }
        .padding(10)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous)
            .strokeBorder(tab.waiting > 0 ? AnyShapeStyle(Color.orange.opacity(0.7)) : AnyShapeStyle(.separator), lineWidth: 1))
    }
}

/// One pane, a native button that focuses it in Rex.
struct RexPaneTile: View {
    let pane: RexOverview.Pane
    let mode: RexOverviewModel.Mode
    let focused: Bool
    let action: () -> Void

    private var tint: Color {
        switch pane.state {
        case .blocked: return .orange
        case .error: return .red
        case .done: return .green
        case .working: return .accentColor
        case .idle: return .secondary
        }
    }

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
            .help("Focus " + pane.name + " in Rex")
            .accessibilityLabel(accessibilityText)
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

    private var heading: some View {
        HStack(spacing: 4) {
            Image(systemName: symbol).foregroundStyle(tint)
            Text(pane.program ?? pane.name).lineLimit(1)
            Spacer(minLength: 2)
            Text(pane.state.title).foregroundStyle(.secondary).lineLimit(1)
        }
        .font(.system(size: 10, weight: .medium))
    }

    @ViewBuilder private var content: some View {
        if mode == .preview, let lines = pane.preview {
            Text(lines.joined(separator: "\n"))
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

    private var outline: some View {
        RoundedRectangle(cornerRadius: 6, style: .continuous)
            .strokeBorder(focused ? tint.opacity(0.8) : Color.clear, lineWidth: 1)
    }
}
