import Foundation

@objc protocol VolantAgentHostProtocol {
    func listAppleShortcuts(reply: @escaping (Data?, String?) -> Void)
    func runAppleShortcut(id: String, reply: @escaping (String?) -> Void)
    func acpStart(provider: String, project: String, reply: @escaping (String?) -> Void)
    func acpRead(reply: @escaping (Data?, String?) -> Void)
    func acpPrompt(text: String, reply: @escaping (String?) -> Void)
    func acpCancel(reply: @escaping (String?) -> Void)
    func acpPermission(request: String, option: String, reply: @escaping (String?) -> Void)
    func acpStop(reply: @escaping () -> Void)
    func answerAgentQuestion(token: String, choice: Int, reply: @escaping (String?, String?) -> Void)
    func readAgentAttention(paneID: String, terminalID: String, sessionIdentity: String, reply: @escaping (Data?, String?) -> Void)
    func listAgents(reply: @escaping (Data?, String?) -> Void)
    func focusAgent(paneID: String, terminalID: String, sessionIdentity: String, reply: @escaping (String?) -> Void)
}

struct AgentSession: Codable, Identifiable, Hashable {
    let agent: String
    let agentStatus: String
    let paneID: String
    let terminalID: String
    let cwd: String?
    let terminalTitle: String?
    struct SessionReference: Codable, Hashable { let value: String }
    let agentSession: SessionReference?
    var stateChangeSequence: UInt64? = nil
    var sessionIdentity: String { agent + ":" + (agentSession?.value ?? terminalID) }
    var id: String { terminalID + ":" + paneID }
    var project: String { cwd.map { URL(fileURLWithPath: $0).lastPathComponent } ?? "Unknown project" }
    var provider: String {
        switch agent {
        case "claude": return "Claude Code"
        case "codex": return "Codex"
        case "opencode": return "OpenCode"
        case "cursor": return "Cursor"
        default: return agent.capitalized
        }
    }
    var status: String {
        switch agentStatus {
        case "blocked": return "Needs attention"
        case "working": return "Working"
        case "done": return "Done"
        case "idle": return "Idle"
        default: return "Unknown"
        }
    }
    var priority: Int { ["blocked": 0, "working": 1, "done": 2, "idle": 3][agentStatus] ?? 4 }
    enum CodingKeys: String, CodingKey {
        case agent, cwd
        case stateChangeSequence = "state_change_seq"
        case agentStatus = "agent_status"
        case paneID = "pane_id"
        case terminalID = "terminal_id"
        case terminalTitle = "terminal_title_stripped"
        case agentSession = "agent_session"
    }
    static func decodeList(_ data: Data) throws -> [AgentSession] {
        struct Envelope: Decodable { struct Result: Decodable { let agents: [AgentSession] }; let result: Result }
        return try JSONDecoder().decode(Envelope.self, from: data).result.agents.sorted {
            if $0.priority != $1.priority { return $0.priority < $1.priority }
            if $0.project != $1.project { return $0.project.localizedStandardCompare($1.project) == .orderedAscending }
            return $0.id < $1.id
        }
    }
}
