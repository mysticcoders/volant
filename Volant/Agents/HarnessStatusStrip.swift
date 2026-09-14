import SwiftUI

struct HarnessStatusStrip: View {
    let title: String
    let sessions: [AgentSession]
    let connected: Bool
    let busy: Bool
    let pinned: Bool
    let onOpen: () -> Void
    let onConnect: () -> Void
    let onPromote: (String?) -> Void
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: !pinned ? "terminal" : "pin.fill")
                .foregroundStyle(.secondary)
            Button(!pinned ? "Herdr" : title) {
                onOpen()
            }.buttonStyle(.plain).fontWeight(.medium)
            if connected {
                let attention = sessions.filter { $0.agentStatus == "blocked" }.count
                let working = sessions.filter { $0.agentStatus == "working" }.count
                Text("\(sessions.count) panes · \(working) working" + (attention > 0 ? " · \(attention) need you" : ""))
                    .foregroundStyle(attention > 0 ? Color.orange : Color.secondary)
                    .lineLimit(1)
                    .accessibilityLabel("\(sessions.count) panes, \(working) working, \(attention) need attention")
            } else {
                Text("Not connected").foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            if busy { ProgressView().controlSize(.mini) }
            Button(connected ? "Disconnect" : "Connect") {
                onConnect()
            }.buttonStyle(.borderless)
            Menu {
                Button("Don’t pin a harness") { onPromote(nil) }
                Divider()
                ForEach(Preferences.harnessOptions, id: \.id) { option in
                    Button(option.title) { onPromote(option.id) }
                }
            } label: {
                Image(systemName: "pin")
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .help("Promote a harness below the search field")
            .accessibilityLabel("Pin harness status")
        }
        .font(.system(size: 12))
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
        .background(Color.primary.opacity(0.025))
    }

}
