import SwiftUI

/// One passive question preview at a time, below the pinned status bar.
struct HerdrAttentionView: View {
    @ObservedObject var model: AgentsModel
    let sessions: [AgentSession]
    @State private var selectedID: String?
    private var waiting: [AgentSession] { sessions.filter { $0.agentStatus == "blocked" } }
    private var selected: AgentSession? { waiting.first { $0.id == selectedID } ?? waiting.first }
    private var identity: String { selected.map { $0.id + ":" + $0.sessionIdentity } ?? "" }

    var body: some View {
        Group {
            if model.connected, let session = selected {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        Image(systemName: "questionmark.bubble").foregroundStyle(.orange)
                        Text(session.provider + " · " + session.project).fontWeight(.medium).lineLimit(1)
                        Spacer(minLength: 4)
                        if waiting.count > 1 {
                            Button { advance(-1) } label: { Image(systemName: "chevron.left") }
                                .accessibilityLabel("Previous waiting agent")
                            Text("\((waiting.firstIndex { $0.id == session.id } ?? 0) + 1) of \(waiting.count)")
                                .foregroundStyle(.secondary)
                            Button { advance(1) } label: { Image(systemName: "chevron.right") }
                                .accessibilityLabel("Next waiting agent")
                        }
                        if model.attentionLoading { ProgressView().controlSize(.mini) }
                    }
                    if !model.isAttentionTarget(session) {
                        Text("Reading the current question…").foregroundStyle(.secondary)
                    } else if let error = model.attentionError {
                        Text(error).foregroundStyle(.secondary)
                    } else if let preview = model.attention, !preview.text.isEmpty {
                        ScrollView {
                            Text(preview.text).textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }.frame(maxHeight: 90)
                        if preview.truncated { Text("Showing the end of the prompt. Review the full context in Herdr.").foregroundStyle(.secondary) }
                    } else {
                        Text(model.attentionLoading ? "Reading the current question…" : "This agent needs input. Review the question in Herdr.")
                            .foregroundStyle(.secondary)
                    }
                    HStack {
                        Text("Reply in the agent’s pane").foregroundStyle(.secondary)
                        Spacer()
                        Button("Refresh", action: model.refreshAttention).disabled(model.attentionLoading)
                        Button("Open in Herdr") { model.focus(session) }
                            .disabled(model.busy)
                            .help("Select this pane in Herdr, then switch to your Herdr terminal")
                    }
                    if let message = model.actionMessage { Text(message).foregroundStyle(.secondary) }
                }
                .font(.system(size: 12))
                .padding(.horizontal, 20).padding(.vertical, 10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.orange.opacity(0.06))
            }
        }
        .task(id: identity) { model.watchAttention(selected) }
        .onDisappear { model.watchAttention(nil) }
    }

    private func advance(_ direction: Int) {
        guard let selected, let index = waiting.firstIndex(where: { $0.id == selected.id }), !waiting.isEmpty else { return }
        selectedID = waiting[(index + direction + waiting.count) % waiting.count].id
    }
}
