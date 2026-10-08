import SwiftUI
import VolantCore

/// The top of the `herdr` view: the waiting question, if any, then machine status and controls.
/// It observes the agents model itself so the launcher view does not have to.
struct HerdrQueryHeader: View {
    @ObservedObject var agents: AgentsModel
    let onNewConversation: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            HerdrAttentionView(model: agents, sessions: agents.sessions)
            if let message = agents.actionMessage {
                Text(message).font(.system(size: 12)).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 20).padding(.vertical, 8)
            }
            HerdrMachineStatusView(machines: agents.machines)
                .padding(.horizontal, 20)
            HStack {
                Text("Herdr panes").foregroundStyle(.secondary)
                Spacer()
                Button(agents.connected ? "Disconnect" : "Connect") {
                    if agents.connected { agents.disconnect() } else { agents.connect() }
                }
                Button("New ACP conversation", action: onNewConversation)
            }.font(.system(size: 12)).padding(.horizontal, 20).padding(.vertical, 6)
        }
    }
}

/// Each machine's connection state in the `herdr` view.
struct HerdrMachineStatusView: View {
    let machines: [HerdrMachineStatus]
    var body: some View {
        if !machines.isEmpty {
            ScrollView(.horizontal) {
                HStack(spacing: 12) {
                    ForEach(machines) { machine in
                        HStack(spacing: 4) {
                            if machine.state == "loading" { ProgressView().controlSize(.mini) }
                            Label(machine.label + " · " + machine.state.capitalized,
                                  systemImage: machine.unavailable ? "exclamationmark.triangle" : "desktopcomputer")
                        }
                            .foregroundStyle(machine.unavailable ? Color.orange : Color.secondary)
                            .help(machine.detail)
                            .accessibilityLabel(machine.label + ". " + machine.state + ". " + machine.detail)
                    }
                }
            }.font(.system(size: 11)).frame(maxHeight: 24)
        }
    }
}
