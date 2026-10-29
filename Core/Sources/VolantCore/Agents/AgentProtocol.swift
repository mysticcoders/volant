import Foundation

@objc public protocol VolantAgentHostProtocol {
    func listAppleShortcuts(reply: @escaping (Data?, String?) -> Void)
    func runAppleShortcut(id: String, reply: @escaping (String?) -> Void)
    /// Starts the provider in `project`. `profile` is an account folder, passed to the provider as
    /// its one account variable (`ACPAccountProfile.launchVariables`), or "" for its default login.
    /// The helper checks only that the folder exists and reads nothing in it. A refused folder
    /// starts nothing.
    func acpStart(provider: String, project: String, profile: String, reply: @escaping (String?) -> Void)
    /// Starts the provider under `profile`, as `acpStart` does, and loads a conversation it created
    /// earlier, by its recorded native session ID. The reply reports only a refused ID, a refused
    /// account folder or a failed launch; when the agent cannot load the conversation, it ends as
    /// failed in `acpRead` and no new conversation starts.
    func acpResume(provider: String, project: String, profile: String, session: String, reply: @escaping (String?) -> Void)
    /// The conversation as a JSON `ACPStateUpdate` with its revision. When `after` is already the
    /// current revision the reply carries no data: nothing changed. When `after` is the revision the
    /// helper sent last, the update carries only the messages changed since; any other `after`,
    /// including a negative one, gets the full state.
    func acpRead(after revision: Int, reply: @escaping (Data?, Int, String?) -> Void)
    func acpPrompt(text: String, reply: @escaping (String?) -> Void)
    /// A prompt with owner-chosen attachments, a JSON array of `ChatAttachment`.
    func acpPromptWithContext(text: String, attachments: Data, reply: @escaping (String?) -> Void)
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
    /// Rex panes and the status their programs reported, as JSON `RexInventory`, from a watcher the
    /// helper starts on the first read and keeps running while reads continue. The reply carries the
    /// watcher's revision. When `after` is already current, the reply waits up to two seconds for a
    /// change; if none comes it carries no data and no message: nothing changed. Otherwise it carries the latest panes, or none and a message such as Rex not
    /// running. Reads only layout, status records and reported directories, never a pane's screen,
    /// and never starts Rex.
    func readRexPanes(after revision: Int, reply: @escaping (Data?, Int, String?) -> Void)
    /// The same watcher's sessions, tabs and positioned panes, as JSON `RexOverview`, with the same
    /// revision and holding rules as `readRexPanes`. With `preview`, which the app sends only after
    /// the owner turned on pane previews, panes carry the last lines of their screen text; the helper
    /// stops reading screens a few seconds after reads stop asking for them.
    func readRexOverview(after revision: Int, preview: Bool, reply: @escaping (Data?, Int, String?) -> Void)
    /// Stops the watcher. The next read starts a new one.
    func stopRexPanes(reply: @escaping () -> Void)
    /// Focuses a Rex pane after checking it is still a terminal in that session, then asks the Rex
    /// app to show the session. The reply is nil only when the app switched to it; otherwise it is a
    /// message to show, such as Remote Control being off in Rex.
    func focusRexPane(session: String, block: String, reply: @escaping (String?) -> Void)
    /// Every known ACP provider and whether its executable is present. Starts nothing.
    func detectACPAgents(reply: @escaping (Data?, String?) -> Void)
    /// Change counts for up to 32 local working folders, as a JSON map from path to state.
    func repositoryStates(paths: Data, reply: @escaping (Data?, String?) -> Void)
    /// Asks a running fsearch daemon for files matching `query`, as JSON `[FSearch.Hit]`. Volant never
    /// starts fsearch; with no daemon the reply is an error and the caller uses Spotlight instead.
    func fsearchSearch(query: String, limit: Int, reply: @escaping (Data?, String?) -> Void)
    /// The daemon's `FSearch.Status` as JSON, or an error when it isn't running.
    func fsearchStatus(reply: @escaping (Data?, String?) -> Void)
    /// Tells fsearch the owner opened `path`, so it ranks higher. Best effort.
    func fsearchOpened(path: String, reply: @escaping (String?) -> Void)
    /// The TCP ports the owner's own processes are listening on, as JSON `[ListeningServer]`, read
    /// fresh on each call and kept nowhere. Takes no input and acts on no process. Carries each
    /// process's executable path and working folder, never its arguments or environment.
    func listListeningServers(reply: @escaping (Data?, String?) -> Void)
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
    public var machineLabel: String { machine?.label ?? String(localized: "Local", table: "Core", comment: "Herdr machine name for this Mac") }
    public var stateChangeSequence: UInt64? = nil
    /// Whether Herdr reports this pane as the one in front, which counts as having looked at it.
    public var focused: Bool? = nil
    public var sessionIdentity: String { agent + ":" + (agentSession?.value ?? terminalID) }
    public var id: String { (machine.map { "remote:" + $0.routeIdentity + ":" } ?? "local:") + terminalID + ":" + paneID }
    /// The folder name, taken from the path string alone. `URL(fileURLWithPath:)` checks the file
    /// system, and on the main thread a sandboxed lookup of every pane's folder stalled typing.
    public var project: String { cwd.map { ($0 as NSString).lastPathComponent } ?? String(localized: "Unknown project", table: "Core", comment: "Agent pane whose folder is unknown") }
    public var provider: String {
        switch agent {
        case "claude": return "Claude Code"
        case "codex": return "Codex"
        case "opencode": return "OpenCode"
        case "cursor": return "Cursor"
        case "gemini": return "Gemini CLI"
        case "qwen": return "Qwen Code"
        default: return agent.capitalized
        }
    }
    public var status: String {
        switch agentStatus {
        case "blocked": return String(localized: "Needs attention", table: "Core", comment: "Agent pane status: the agent is waiting for the owner")
        case "working": return String(localized: "Working", table: "Core", comment: "Agent pane status: the agent is busy")
        case "done": return String(localized: "Done", table: "Core", comment: "Agent pane status: the agent finished")
        case "idle": return String(localized: "Idle", table: "Core", comment: "Agent pane status: the agent is idle")
        default: return String(localized: "Unknown", table: "Core", comment: "Agent pane status Herdr reported that Volant doesn't recognize")
        }
    }
    public var priority: Int { ["blocked": 0, "working": 1, "done": 2, "idle": 3][agentStatus] ?? 4 }
    public enum CodingKeys: String, CodingKey {
        case agent, cwd, machine, focused
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
    /// Orders panes by attention priority, project name, then identity, computing each pane's keys
    /// once rather than on every comparison during each Herdr refresh.
    public static func sorted(_ agents: [AgentSession]) -> [AgentSession] {
        agents.map { (agent: $0, priority: $0.priority, project: $0.project, id: $0.id) }
            .sorted {
                if $0.priority != $1.priority { return $0.priority < $1.priority }
                if $0.project != $1.project { return $0.project.localizedStandardCompare($1.project) == .orderedAscending }
                return $0.id < $1.id
            }
            .map(\.agent)
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
