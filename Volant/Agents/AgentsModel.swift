import AppKit
import SwiftUI
import VolantCore

/// UI-owned model; callbacks are delivered on the main queue.
final class AgentsModel: ObservableObject {
    @Published var sessions: [AgentSession] = []
    @Published var machines: [HerdrMachineStatus] = []
    @Published var connected = false
    @Published var busy = false
    @Published var message = "Connect to Local and enabled machines saved in Herdr."
    @Published var actionMessage: String?
    @Published var query = ""
    @Published private(set) var attention: HerdrAttention?
    @Published private(set) var attentionLoading = false
    @Published private(set) var attentionError: String?
    @Published private(set) var attentionQuestion: HerdrQuestion?
    @Published private(set) var attentionAnswering = false
    @Published private(set) var attentionResponse: String?
    private var answerRequest = UUID()
    private var attentionToken: String?
    var attentionResponder: ((String, Int, @escaping (String?, String?) -> Void) -> Void)?
    private var attentionTarget: AgentSession?
    private var attentionRequest = UUID()
    // Injected only by isolated fixtures; production reads through the signed helper.
    var attentionReader: ((AgentSession, @escaping (Data?, String?) -> Void) -> Void)?
    // Injectable transport for deterministic, isolated progressive-loading tests.
    var inventoryReader: ((HerdrMachine?, @escaping (Data?, String?) -> Void) -> Void)?
    var machineWriter: ((HerdrMachine, Bool, @escaping (Data?, String?) -> Void) -> Void)?
    @Published private(set) var machineToggleInFlight: String?
    var machineReader: ((@escaping (Data?, String?) -> Void) -> Void)?
    @Published private(set) var profiles: [HerdrMachine] = []
    /// Change counts keyed by local working folder, shared by every pane in that folder.
    @Published private(set) var repositories: [String: RepositoryState] = [:]
    // Injected only by isolated fixtures; production reads through the signed helper.
    var repositoryReader: (([String], @escaping (Data?, String?) -> Void) -> Void)?
    private var repositoryRequest: UUID?
    private var repositoryMarks: [String: UInt64] = [:]
    private var repositoryCheckedAt: [String: Date] = [:]
    /// Herdr's state-change counter as of the last time the owner looked at each pane. A pane is
    /// unread when the counter has moved since then and the agent is now waiting, not working.
    @Published private var seen: [String: UInt64] = [:]
    private var catalogRequest: UUID?
    private var inventoryRequests: [String: UUID] = [:]
    private var connection: NSXPCConnection?
    private var timer: Timer?
    private var generation = 0
    private var focusInFlight = false
    private(set) var lastFocusSucceeded: Bool?
    var filtered: [AgentSession] {
        sessions.filter { query.isEmpty || [$0.machineLabel, $0.project, $0.provider, $0.status, $0.terminalTitle ?? "", $0.cwd ?? ""].joined(separator: " ").localizedCaseInsensitiveContains(query) }
    }
    func connect() {
        disconnect()
        let connection = NSXPCConnection(serviceName: "com.mysticcoders.volant.AgentHost")
        connection.remoteObjectInterface = NSXPCInterface(with: VolantAgentHostProtocol.self)
        let current = generation
        connection.interruptionHandler = { [weak self] in DispatchQueue.main.async { self?.failed("Local helper disconnected. Reconnect to try again.", generation: current) } }
        connection.invalidationHandler = { [weak self] in DispatchQueue.main.async { self?.failed("Local helper is unavailable. Reconnect to try again.", generation: current) } }
        self.connection = connection
        connection.resume()
        connected = true
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in Task { @MainActor in self?.refresh() } }
    }
    func disconnect() {
        generation += 1
        profiles = []; catalogRequest = nil; inventoryRequests = [:]
        watchAttention(nil)
        timer?.invalidate(); timer = nil
        connection?.invalidate(); connection = nil
        connected = false; busy = false; focusInFlight = false; sessions = []; machines = []; actionMessage = nil; machineToggleInFlight = nil
        repositories = [:]; repositoryRequest = nil; repositoryMarks = [:]; repositoryCheckedAt = [:]
        message = "Connect to Local and enabled machines saved in Herdr."
    }
    private func failed(_ error: String, generation current: Int) {
        guard current == generation else { return }
        disconnect()
        message = error
    }
    func refresh() {
        guard connected, connection != nil || inventoryReader != nil else { return }
        loadInventory(on: nil)
        for machine in profiles where machine.enabled { loadInventory(on: machine) }
        guard catalogRequest == nil else { return }
        let request = UUID(), current = generation
        catalogRequest = request
        updateInventoryMessage()
        let reply: (Data?, String?) -> Void = { [weak self] data, error in
            DispatchQueue.main.async {
                guard let self, self.connected, current == self.generation, self.catalogRequest == request else { return }
                self.catalogRequest = nil
                if let data, let profiles = try? HerdrMachine.decode(data), error == nil {
                    let active = profiles.filter(\.enabled)
                    let validRoutes = Set(active.map(\.routeIdentity))
                    let previousRoutes = Set(self.profiles.filter(\.enabled).map(\.routeIdentity))
                    let validIDs = Set(profiles.map { "remote:" + $0.id })
                    for old in self.profiles where !validRoutes.contains(old.routeIdentity) {
                        self.inventoryRequests.removeValue(forKey: "remote:" + old.id)
                        self.machines.removeAll { $0.id == "remote:" + old.id }
                    }
                    self.sessions.removeAll { $0.machine.map { !validRoutes.contains($0.routeIdentity) } ?? false }
                    self.machines.removeAll { $0.id == "catalog" || ($0.id != "local" && !validIDs.contains($0.id)) }
                    self.profiles = profiles
                    for machine in profiles {
                        if machine.enabled {
                            if !previousRoutes.contains(machine.routeIdentity) { self.loadInventory(on: machine) }
                        }
                        else { self.setMachine(.init(id: "remote:" + machine.id, label: machine.label, state: "disabled", detail: "Disabled in Herdr")) }
                    }
                } else {
                    // An unreadable catalog cannot authorize stale remote panes.
                    self.profiles = []
                    self.inventoryRequests = self.inventoryRequests.filter { $0.key == "local" }
                    self.sessions.removeAll { $0.machine != nil }
                    self.machines.removeAll { $0.id != "local" }
                    self.setMachine(.init(id: "catalog", label: "Saved machines", state: "unavailable",
                        detail: error ?? "Couldn’t read saved machines."))
                }
                self.refreshAttention()
                self.updateInventoryMessage()
            }
        }
        if let machineReader { machineReader(reply) }
        else { inventoryProxy()?.listHerdrMachines(reply: reply) }
    }

    /// Turns a saved machine on or off. Herdr owns the state, so the reply's catalog is applied
    /// rather than the value that was requested, and a full refresh follows so panes on a machine
    /// just switched on appear and panes on one just switched off are dropped.
    func setMachineEnabled(_ machine: HerdrMachine, _ enabled: Bool) {
        guard connected, machineToggleInFlight == nil else { return }
        guard let data = try? JSONEncoder().encode(machine) else { return }
        let current = generation
        machineToggleInFlight = machine.id
        actionMessage = (enabled ? "Enabling " : "Disabling ") + machine.label + "…"
        let apply: (Data?, String?) -> Void = { [weak self] reply, error in
            DispatchQueue.main.async {
                guard let self, current == self.generation else { return }
                self.machineToggleInFlight = nil
                if let reply, let profiles = try? HerdrMachine.decode(reply), error == nil {
                    self.profiles = profiles
                    let state = profiles.first { $0.id == machine.id }?.enabled
                    self.actionMessage = machine.label + " is " + ((state ?? enabled) ? "enabled" : "disabled") + "."
                    self.refresh()
                } else {
                    self.actionMessage = error ?? "Couldn’t change this machine in Herdr."
                }
            }
        }
        if let machineWriter { machineWriter(machine, enabled, apply) }
        else { inventoryProxy()?.setHerdrMachine(machine: data, enabled: enabled, reply: apply) }
    }

    private func inventoryProxy() -> VolantAgentHostProtocol? {
        let current = generation
        return connection?.remoteObjectProxyWithErrorHandler { [weak self] _ in
            DispatchQueue.main.async { self?.failed("Local helper disconnected. Reconnect to try again.", generation: current) }
        } as? VolantAgentHostProtocol
    }

    private func loadInventory(on machine: HerdrMachine?) {
        let id = machine.map { "remote:" + $0.id } ?? "local"
        guard inventoryRequests[id] == nil else { return }
        let request = UUID(), current = generation
        inventoryRequests[id] = request
        if !machines.contains(where: { $0.id == id && $0.state == "connected" }) {
            setMachine(.init(id: id, label: machine?.label ?? "Local", state: "loading", detail: "Loading panes…"))
        }
        updateInventoryMessage()
        let reply: (Data?, String?) -> Void = { [weak self] data, error in
            DispatchQueue.main.async {
                guard let self, self.connected, current == self.generation, self.inventoryRequests[id] == request else { return }
                self.inventoryRequests.removeValue(forKey: id)
                self.sessions.removeAll { ($0.machine.map { "remote:" + $0.id } ?? "local") == id }
                let values = data.flatMap { try? JSONDecoder().decode([AgentSession].self, from: $0) }
                if let values, error == nil, values.allSatisfy({ $0.machine?.routeIdentity == machine?.routeIdentity }) {
                    self.sessions = AgentSession.sorted(self.sessions + values)
                    self.noteSeen(values)
                    if machine == nil { self.refreshRepositories() }
                    self.setMachine(.init(id: id, label: machine?.label ?? "Local", state: "connected", detail: "\(values.count) panes"))
                } else {
                    self.setMachine(.init(id: id, label: machine?.label ?? "Local", state: "unavailable", detail: error ?? "Couldn’t read panes."))
                }
                self.refreshAttention()
                self.updateInventoryMessage()
            }
        }
        if let inventoryReader { inventoryReader(machine, reply) }
        else {
            do { inventoryProxy()?.listAgents(machine: try machine.map { try JSONEncoder().encode($0) }, reply: reply) }
            catch { reply(nil, "Invalid saved machine.") }
        }
    }

    private func seenKey(_ session: AgentSession) -> String { session.id + "|" + session.sessionIdentity }

    /// A pane seen for the first time starts read, and one Herdr reports as focused is read.
    private func noteSeen(_ values: [AgentSession]) {
        for session in values {
            let key = seenKey(session), sequence = session.stateChangeSequence ?? 0
            if seen[key] == nil || session.focused == true { seen[key] = sequence }
        }
    }

    func isUnread(_ session: AgentSession) -> Bool {
        guard let sequence = session.stateChangeSequence, let last = seen[seenKey(session)] else { return false }
        return sequence > last && ["blocked", "done", "idle"].contains(session.agentStatus)
    }

    func markSeen(_ session: AgentSession) {
        if let sequence = session.stateChangeSequence { seen[seenKey(session)] = sequence }
    }

    var unreadCount: Int { sessions.filter(isUnread).count }

    func repository(for session: AgentSession) -> RepositoryState? {
        guard session.machine == nil, let cwd = session.cwd else { return nil }
        return repositories[cwd]
    }

    /// Re-reads a folder only when one of its panes changed state or thirty seconds have passed,
    /// so the five-second pane refresh does not run git in every repository each time.
    private func refreshRepositories() {
        guard repositoryRequest == nil else { return }
        var marks: [String: UInt64] = [:]
        for session in sessions where session.machine == nil {
            guard let cwd = session.cwd else { continue }
            marks[cwd] = max(marks[cwd] ?? 0, session.stateChangeSequence ?? 0)
        }
        repositories = repositories.filter { marks[$0.key] != nil }
        let now = Date()
        let due = Array(marks.keys.filter {
            repositoryMarks[$0] != marks[$0] || now.timeIntervalSince(repositoryCheckedAt[$0] ?? .distantPast) > 30
        }.sorted().prefix(RepositoryStateLimit.paths))
        guard !due.isEmpty, let data = try? JSONEncoder().encode(due) else { return }
        let request = UUID(), current = generation
        repositoryRequest = request
        let reply: (Data?, String?) -> Void = { [weak self] data, error in
            DispatchQueue.main.async {
                guard let self, self.connected, current == self.generation, self.repositoryRequest == request else { return }
                self.repositoryRequest = nil
                let states = error == nil ? data.flatMap { try? JSONDecoder().decode([String: RepositoryState].self, from: $0) } : nil
                for cwd in due {
                    self.repositoryCheckedAt[cwd] = Date()
                    guard let states else { continue }
                    self.repositoryMarks[cwd] = marks[cwd]
                    self.repositories[cwd] = states[cwd]
                }
            }
        }
        if let repositoryReader { repositoryReader(due, reply) }
        else { inventoryProxy()?.repositoryStates(paths: data, reply: reply) }
    }

    private func setMachine(_ value: HerdrMachineStatus) {
        machines.removeAll { $0.id == value.id }
        machines.append(value)
        machines.sort {
            if $0.id == "local" { return true }; if $1.id == "local" { return false }
            return $0.label == $1.label ? $0.id < $1.id : $0.label.localizedStandardCompare($1.label) == .orderedAscending
        }
    }

    private func updateInventoryMessage() {
        busy = catalogRequest != nil || !inventoryRequests.isEmpty
        if machines.contains(where: \.unavailable) { message = "Some machines are unavailable. Showing connected machines only." }
        else if busy { message = "Loading Herdr machines… Available panes are ready to use." }
        else { message = sessions.isEmpty ? "No agents are running on connected machines." : "Herdr machines · refreshes automatically" }
    }
    func isAttentionTarget(_ session: AgentSession) -> Bool {
        attentionTarget?.id == session.id && attentionTarget?.sessionIdentity == session.sessionIdentity
    }

    func watchAttention(_ session: AgentSession?) {
        if attentionTarget?.id == session?.id && attentionTarget?.sessionIdentity == session?.sessionIdentity { return }
        attentionRequest = UUID(); answerRequest = UUID()
        attentionTarget = session
        attention = nil; attentionError = nil; attentionLoading = false
        attentionQuestion = nil; attentionToken = nil; attentionResponse = nil; attentionAnswering = false
        refreshAttention()
    }

    func refreshAttention() {
        guard !attentionAnswering, let target = attentionTarget else { return }
        guard connected, HerdrAttention.matches(target, in: sessions) else {
            attentionRequest = UUID(); attention = nil; attentionError = nil; attentionLoading = false
            attentionQuestion = nil; attentionToken = nil
            return
        }
        guard !attentionLoading, !attentionAnswering else { return }
        let request = UUID(); attentionRequest = request
        attentionLoading = true
        let completion: (Data?, String?) -> Void = { [weak self] data, error in
            DispatchQueue.main.async {
                guard let self, self.attentionRequest == request, self.connected,
                      HerdrAttention.matches(target, in: self.sessions) else { return }
                self.attentionLoading = false
                let snapshot = data.flatMap { try? JSONDecoder().decode(HerdrResponseController.Snapshot.self, from: $0) }
                // A post-send read can race the provider leaving its question screen. Preserve
                // the delivery result (including uncertainty) until a fresh screen or list arrives.
                if snapshot == nil, self.attentionResponse != nil {
                    self.attentionError = nil
                    return
                }
                if self.attentionQuestion?.fingerprint != snapshot?.question?.fingerprint {
                    self.attentionResponse = nil
                    self.actionMessage = nil
                }
                self.attention = snapshot.flatMap { try? HerdrAttention.preview(Data($0.text.utf8)) }
                self.attentionQuestion = snapshot?.question
                self.attentionToken = snapshot?.token
                self.attentionError = error ?? (self.attention == nil ? "Couldn’t read this question. Open it in Herdr." : nil)
            }
        }
        if let attentionReader { attentionReader(target, completion); return }
        guard let connection else { completion(nil, "Herdr is disconnected."); return }
        let proxy = connection.remoteObjectProxyWithErrorHandler { _ in completion(nil, "Couldn’t read this question. Open it in Herdr.") } as? VolantAgentHostProtocol
        guard let data = try? JSONEncoder().encode(target) else { completion(nil, "Invalid agent destination."); return }
        proxy?.readAgentAttention(target: data, reply: completion)
    }

    var canAnswerAttention: Bool { connected && !attentionLoading && !attentionAnswering && attentionToken != nil }
    func answerAttention(_ choice: Int) {
        guard canAnswerAttention, let token = attentionToken, let target = attentionTarget,
              HerdrAttention.matches(target, in: sessions),
              attentionQuestion?.answerChoices.contains(where: { $0.number == choice }) == true else { return }
        attentionToken = nil; attentionAnswering = true; attentionResponse = "Sending answer…"
        attentionRequest = UUID()
        answerRequest = UUID()
        let request = answerRequest
        let completion: (String?, String?) -> Void = { [weak self] status, error in
            DispatchQueue.main.async {
                guard let self, self.answerRequest == request else { return }
                self.attentionAnswering = false
                self.attentionResponse = error ?? status
                if error == nil { self.markSeen(target) }
                self.actionMessage = error ?? status
                self.attentionError = error
                self.refresh()
            }
        }
        if let attentionResponder { attentionResponder(token, choice, completion); return }
        guard let connection else { completion(nil, "Herdr is disconnected."); return }
        let proxy = connection.remoteObjectProxyWithErrorHandler { _ in completion(nil, "Couldn’t confirm delivery. Review Herdr before retrying.") } as? VolantAgentHostProtocol
        proxy?.answerAgentQuestion(token: token, choice: choice, reply: completion)
    }

    func focus(_ session: AgentSession) {
        guard connected, !focusInFlight, let connection else { return }
        focusInFlight = true
        let current = generation
        let proxy = connection.remoteObjectProxyWithErrorHandler { [weak self] error in
            DispatchQueue.main.async { self?.failed(error.localizedDescription, generation: current) }
        } as? VolantAgentHostProtocol
        guard let data = try? JSONEncoder().encode(session) else { focusInFlight = false; return }
        proxy?.focusAgent(target: data) { [weak self] error in
            DispatchQueue.main.async {
                guard let self, self.generation == current else { return }
                self.focusInFlight = false
                self.lastFocusSucceeded = error == nil
                if error == nil { self.markSeen(session) }
                self.actionMessage = error ?? "Focused on \(session.machineLabel). Switch to that machine in Herdr to continue."
                if error == nil { self.refresh() }
            }
        }
    }
}
