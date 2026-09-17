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
    var machines: [HerdrMachineStatus] = []
    @AppStorage("showHerdrDetails") private var showDetails = false
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Image(systemName: "waveform.path")
                    .foregroundStyle(Color.accentColor)
                Button(!pinned ? "Herdr" : title) {
                    onOpen()
                }.buttonStyle(.plain).fontWeight(.medium)
                if connected {
                    let attention = sessions.filter { $0.agentStatus == "blocked" }.count
                    let working = sessions.filter { $0.agentStatus == "working" }.count
                    Text("\(sessions.count) panes · \(working) working" + (attention > 0 ? " · \(attention) \(attention == 1 ? "needs" : "need") you" : ""))
                        .foregroundStyle(attention > 0 ? Color.orange : Color.secondary)
                        .lineLimit(1)
                        .accessibilityLabel("\(sessions.count) panes, \(working) working, \(attention) need attention")
                } else {
                    Text("Not connected").foregroundStyle(.secondary)
                }
                if machines.contains(where: \.unavailable) {
                    Image(systemName: "exclamationmark.triangle")
                        .foregroundStyle(.orange)
                        .accessibilityLabel("Some Herdr machines are unavailable")
                        .help(machines.filter(\.unavailable).map { $0.label + ": " + $0.detail }.joined(separator: "\n"))
                }
                Spacer(minLength: 0)
                if busy { ProgressView().controlSize(.mini) }
                if !connected {
                    Button("Connect", action: onConnect).buttonStyle(.borderless)
                }
                Button { showDetails.toggle() } label: {
                    Image(systemName: showDetails ? "chevron.up" : "chevron.down")
                }
                .buttonStyle(.borderless)
                .accessibilityLabel(showDetails ? "Hide Herdr pane details" : "Show Herdr pane details")
                .help("Show project, provider, and status without opening Agents")
                Menu {
                    Button("Hide Herdr status") { onPromote(nil) }
                    Divider()
                    ForEach(Preferences.harnessOptions, id: \.id) { option in
                        Button(option.title) { onPromote(option.id) }
                    }
                } label: {
                    Image(systemName: "slider.horizontal.3")
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                .help("Configure Herdr status")
                .accessibilityLabel("Configure status bar")
            }
            .font(.system(size: 12))
            .padding(.horizontal, 20)
            .padding(.vertical, 10)
            .background(Color.accentColor.opacity(0.06))
            if showDetails && connected {
                ScrollView {
                    VStack(spacing: 6) {
                        HerdrMachineStatusView(machines: machines)
                        if sessions.isEmpty {
                            Text(busy ? "Loading panes…" : "No matching panes")
                                .foregroundStyle(.secondary)
                        }
                        ForEach(sessions.sorted { $0.priority == $1.priority ? $0.id < $1.id : $0.priority < $1.priority }) { session in
                            HarnessPaneSummary(session: session)
                        }
                    }.padding(.horizontal, 20).padding(.vertical, 8)
                }
                .font(.system(size: 12))
                .frame(maxHeight: 112)
            }
        }
    }

}

private struct HarnessPaneSummary: View {
    let session: AgentSession
    private var statusColor: Color {
        if session.agentStatus == "blocked" { return .orange }
        if session.agentStatus == "working" { return .accentColor }
        return .secondary
    }
    private var providerLabel: String { session.machineLabel + " · " + session.provider + " · " + session.paneID }
    private var helpText: String { [session.machineLabel, session.project, session.provider, session.paneID, session.status].joined(separator: " · ") }
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: session.agentStatus == "blocked" ? "exclamationmark.circle.fill" : "circle.fill")
                .font(.system(size: 8))
                .foregroundStyle(statusColor)
            Text(session.project).fontWeight(.medium).lineLimit(1)
            Text(providerLabel).foregroundStyle(.secondary).lineLimit(1)
            Spacer(minLength: 8)
            Text(session.status).foregroundStyle(.secondary)
        }
        .help(helpText)
        .accessibilityElement(children: .combine)
    }
}

/// Shared by the Agents destination and expanded pinned status.
struct HerdrMachineStatusView: View {
    let machines: [HerdrMachineStatus]
    var body: some View {
        if !machines.isEmpty {
            ScrollView(.horizontal) {
                HStack(spacing: 12) {
                    ForEach(machines) { machine in
                        Label(machine.label + " · " + machine.state.capitalized,
                              systemImage: machine.unavailable ? "exclamationmark.triangle" : "desktopcomputer")
                            .foregroundStyle(machine.unavailable ? Color.orange : Color.secondary)
                            .help(machine.detail)
                            .accessibilityLabel(machine.label + ". " + machine.state + ". " + machine.detail)
                    }
                }
            }.font(.system(size: 11)).frame(maxHeight: 24)
        }
    }
}
