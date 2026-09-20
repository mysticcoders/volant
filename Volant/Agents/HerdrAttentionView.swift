import SwiftUI
import VolantCore

/// One waiting agent at a time. Only verified structured questions expose answers.
struct HerdrAttentionView: View {
    @ObservedObject var model: AgentsModel
    let sessions: [AgentSession]
    @State private var selectedID: String?
    @FocusState private var answersFocused: Bool
    private var waiting: [AgentSession] { sessions.filter { $0.agentStatus == "blocked" } }
    private var selected: AgentSession? { waiting.first { $0.id == selectedID } ?? waiting.first }
    private var identity: String { selected.map { $0.id + ":" + $0.sessionIdentity } ?? "" }

    var body: some View {
        Group {
            if model.connected, let session = selected {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        Image(systemName: "questionmark.bubble").foregroundStyle(.orange)
                        Text(session.machineLabel + " · " + session.provider + " · " + session.project).fontWeight(.medium).lineLimit(1)
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
                    } else if let question = model.attentionQuestion {
                        Text(question.title).fontWeight(.medium).fixedSize(horizontal: false, vertical: true)
                        ScrollView {
                            VStack(alignment: .leading, spacing: 6) {
                                if let context = question.displayContext {
                                    Text(context).font(.system(size: 11, design: .monospaced))
                                        .textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                }
                                ForEach(question.answerChoices) { choice in
                                    answerButton(choice)
                                }
                            }.padding(2)
                        }.frame(height: question.context == nil ? min(132, CGFloat(question.answerChoices.count) * 38 + 4) : 132)
                        .focusable().focused($answersFocused)
                        Text(question.context == nil ? "For notes or another answer, open Herdr." : "Review the request and exact approval scope above.").foregroundStyle(.secondary)
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
                        if model.attentionQuestion != nil {
                            Button("Answer with keyboard") { answersFocused = true }
                                .disabled(!model.canAnswerAttention)
                        } else {
                            Text("Reply in the agent’s pane").foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button("Refresh", action: model.refreshAttention).disabled(model.attentionLoading || model.attentionAnswering)
                        Button("Open in Herdr") { model.focus(session) }
                            .disabled(model.attentionAnswering)
                            .help("Select this pane in Herdr, then switch to your Herdr terminal")
                    }
                    if let message = model.attentionResponse ?? model.actionMessage { Text(message).foregroundStyle(.secondary) }
                }
                .layoutPriority(1)
                .font(.system(size: 12))
                .padding(.horizontal, 20).padding(.vertical, 10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.orange.opacity(0.06))
            }
        }
        .task(id: identity) { model.watchAttention(selected) }
        .onDisappear { model.watchAttention(nil) }
    }

    @ViewBuilder private func answerButton(_ choice: HerdrQuestion.Choice) -> some View {
        let button = Button { model.answerAttention(choice.number) } label: {
            HStack {
                Text(choice.label).fontWeight(.medium).fixedSize(horizontal: false, vertical: true)
                Text(choice.detail).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 4)
                if answersFocused { Text("⌥⌘" + String(choice.number)).foregroundStyle(.secondary) }
            }.padding(.horizontal, 8).padding(.vertical, 6)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.primary.opacity(0.08), in: RoundedRectangle(cornerRadius: 6))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!model.canAnswerAttention)
        .accessibilityLabel("Answer " + choice.label + ". " + choice.detail)
        if answersFocused {
            button.keyboardShortcut(KeyEquivalent(Character(String(choice.number))), modifiers: [.command, .option])
        } else {
            button
        }
    }

    private func advance(_ direction: Int) {
        guard let selected, let index = waiting.firstIndex(where: { $0.id == selected.id }), !waiting.isEmpty else { return }
        selectedID = waiting[(index + direction + waiting.count) % waiting.count].id
    }
}
