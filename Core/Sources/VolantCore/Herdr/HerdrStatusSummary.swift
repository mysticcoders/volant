import Foundation

/// The launcher footer's one-line Herdr status, such as "Herdr: 3 waiting".
public struct HerdrStatusSummary: Equatable {
    public enum Tone: Equatable { case quiet, waiting, warning }

    public let text: String
    public let tone: Tone
    public let help: String

    /// A pane is waiting when Herdr reports it blocked, which is how an agent asks for input or
    /// approval. Finished or idle panes are not counted: they need no answer, and the `herdr`
    /// list still marks them as new. An unavailable machine is reported only when nothing is
    /// waiting, so the count that needs the owner always wins the space.
    public init(sessions: [AgentSession], connected: Bool, busy: Bool, machines: [HerdrMachineStatus], unread: Int = 0) {
        let waiting = sessions.filter { $0.agentStatus == "blocked" }.count
        let unavailable = machines.filter(\.unavailable)
        var notes: [String] = []
        if unread > 0 { notes.append("\(unread) changed since you last looked") }
        notes += unavailable.map { $0.label + ": " + $0.detail }
        let suffix = (notes.isEmpty ? "" : "\n" + notes.joined(separator: "\n")) + "\nClick to show Herdr panes."
        if !connected {
            text = "Herdr: not connected"; tone = .quiet
            help = "Herdr isn’t connected." + suffix
        } else if waiting > 0 {
            text = "Herdr: \(waiting) waiting"; tone = .waiting
            help = "\(waiting) \(waiting == 1 ? "agent needs" : "agents need") you." + suffix
        } else if unavailable.count == 1 {
            text = "Herdr: \(unavailable[0].label) unavailable"; tone = .warning
            help = "No agents are waiting." + suffix
        } else if unavailable.count > 1 {
            text = "Herdr: \(unavailable.count) machines unavailable"; tone = .warning
            help = "No agents are waiting." + suffix
        } else if busy && sessions.isEmpty {
            text = "Herdr: loading…"; tone = .quiet
            help = "Loading panes from Herdr." + suffix
        } else {
            text = "Herdr: none waiting"; tone = .quiet
            help = "\(sessions.count) \(sessions.count == 1 ? "pane" : "panes"), none waiting." + suffix
        }
    }
}
