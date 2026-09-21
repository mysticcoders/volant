import Foundation

@objc public protocol VolantAgentHostProtocol {
    func listAppleShortcuts(reply: @escaping (Data?, String?) -> Void)
    func runAppleShortcut(id: String, reply: @escaping (String?) -> Void)
    func acpStart(provider: String, project: String, reply: @escaping (String?) -> Void)
    func acpRead(reply: @escaping (Data?, String?) -> Void)
    func acpPrompt(text: String, reply: @escaping (String?) -> Void)
    func acpCancel(reply: @escaping (String?) -> Void)
    func acpPermission(request: String, option: String, reply: @escaping (String?) -> Void)
    func acpStop(reply: @escaping () -> Void)
    func answerAgentQuestion(token: String, choice: Int, reply: @escaping (String?, String?) -> Void)
    func readAgentAttention(target: Data, reply: @escaping (Data?, String?) -> Void)
    func listHerdrMachines(reply: @escaping (Data?, String?) -> Void)
    /// Turns a saved machine on or off in Herdr, which owns that state, and replies with the
    /// refreshed catalog so the caller never renders the value it requested.
    func setHerdrMachine(machine: Data, enabled: Bool, reply: @escaping (Data?, String?) -> Void)
    func listAgents(machine: Data?, reply: @escaping (Data?, String?) -> Void)
    func focusAgent(target: Data, reply: @escaping (String?) -> Void)
}

public struct AgentSession: Codable, Identifiable, Hashable {
    public let agent: String
    public let agentStatus: String
    public let paneID: String
    public let terminalID: String
    public let cwd: String?
    public let terminalTitle: String?
    public struct SessionReference: Codable, Hashable {
        public let value: String

        public init(value: String) { self.value = value }
    }
    public let agentSession: SessionReference?
    public var machine: HerdrMachine? = nil
    public var machineLabel: String { machine?.label ?? "Local" }
    public var stateChangeSequence: UInt64? = nil
    public var sessionIdentity: String { agent + ":" + (agentSession?.value ?? terminalID) }
    public var id: String { (machine.map { "remote:" + $0.routeIdentity + ":" } ?? "local:") + terminalID + ":" + paneID }
    public var project: String { cwd.map { URL(fileURLWithPath: $0).lastPathComponent } ?? "Unknown project" }
    public var provider: String {
        switch agent {
        case "claude": return "Claude Code"
        case "codex": return "Codex"
        case "opencode": return "OpenCode"
        case "cursor": return "Cursor"
        default: return agent.capitalized
        }
    }
    public var status: String {
        switch agentStatus {
        case "blocked": return "Needs attention"
        case "working": return "Working"
        case "done": return "Done"
        case "idle": return "Idle"
        default: return "Unknown"
        }
    }
    public var priority: Int { ["blocked": 0, "working": 1, "done": 2, "idle": 3][agentStatus] ?? 4 }
    public enum CodingKeys: String, CodingKey {
        case agent, cwd, machine
        case stateChangeSequence = "state_change_seq"
        case agentStatus = "agent_status"
        case paneID = "pane_id"
        case terminalID = "terminal_id"
        case terminalTitle = "terminal_title_stripped"
        case agentSession = "agent_session"
    }
    public static func decodeList(_ data: Data, machine: HerdrMachine? = nil) throws -> [AgentSession] {
        struct Envelope: Decodable { struct Result: Decodable { let agents: [AgentSession] }; let result: Result }
        return sorted(try JSONDecoder().decode(Envelope.self, from: data).result.agents.map { value in
            var value = value; value.machine = machine; return value
        })
    }
    public static func sorted(_ agents: [AgentSession]) -> [AgentSession] {
        agents.sorted {
            if $0.priority != $1.priority { return $0.priority < $1.priority }
            if $0.project != $1.project { return $0.project.localizedStandardCompare($1.project) == .orderedAscending }
            return $0.id < $1.id
        }
    }

    public init(agent: String, agentStatus: String, paneID: String, terminalID: String, cwd: String? = nil, terminalTitle: String? = nil, agentSession: SessionReference? = nil, machine: HerdrMachine? = nil, stateChangeSequence: UInt64? = nil) {
        self.agent = agent
        self.agentStatus = agentStatus
        self.paneID = paneID
        self.terminalID = terminalID
        self.cwd = cwd
        self.terminalTitle = terminalTitle
        self.agentSession = agentSession
        self.machine = machine
        self.stateChangeSequence = stateChangeSequence
    }
}
