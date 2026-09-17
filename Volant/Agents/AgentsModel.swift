import AppKit
import SwiftUI

/// UI-owned model; callbacks are delivered on the main queue.
final class AgentsModel: ObservableObject {
    @Published var sessions: [AgentSession] = []
    @Published var connected = false
    @Published var busy = false
    @Published var message = "Connect to the default local Herdr session to see your running agents."
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
    private var connection: NSXPCConnection?
    private var timer: Timer?
    private var generation = 0
    private(set) var lastFocusSucceeded: Bool?
    var filtered: [AgentSession] {
        sessions.filter { query.isEmpty || [$0.project, $0.provider, $0.status, $0.terminalTitle ?? "", $0.cwd ?? ""].joined(separator: " ").localizedCaseInsensitiveContains(query) }
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
        watchAttention(nil)
        timer?.invalidate(); timer = nil
        connection?.invalidate(); connection = nil
        connected = false; busy = false; sessions = []; actionMessage = nil
        message = "Connect to the default local Herdr session to see your running agents."
    }
    private func failed(_ error: String, generation current: Int) {
        guard current == generation else { return }
        disconnect()
        message = error
    }
    func refresh() {
        guard connected, !busy, let connection else { return }
        busy = true
        let current = generation
        let proxy = connection.remoteObjectProxyWithErrorHandler { [weak self] error in
            DispatchQueue.main.async { self?.failed(error.localizedDescription, generation: current) }
        } as? VolantAgentHostProtocol
        proxy?.listAgents { [weak self] data, error in
            DispatchQueue.main.async {
                guard let self, current == self.generation else { return }
                self.busy = false
                if let error { self.failed(error, generation: current); return }
                do {
                    guard let data else { throw CocoaError(.fileReadCorruptFile) }
                    self.sessions = try AgentSession.decodeList(data)
                    self.refreshAttention()
                    self.message = self.sessions.isEmpty ? "No agents are running in the default Herdr session." : "Local Herdr · updates every 5 seconds"
                } catch { self.failed("Herdr returned an unsupported response.", generation: current) }
            }
        }
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
        proxy?.readAgentAttention(paneID: target.paneID, terminalID: target.terminalID, sessionIdentity: target.sessionIdentity, reply: completion)
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
        guard connected, !busy, let connection else { return }
        busy = true
        let current = generation
        let proxy = connection.remoteObjectProxyWithErrorHandler { [weak self] error in
            DispatchQueue.main.async { self?.failed(error.localizedDescription, generation: current) }
        } as? VolantAgentHostProtocol
        proxy?.focusAgent(paneID: session.paneID, terminalID: session.terminalID, sessionIdentity: session.sessionIdentity) { [weak self] error in
            DispatchQueue.main.async {
                guard let self, self.generation == current else { return }
                self.busy = false
                self.lastFocusSucceeded = error == nil
                self.actionMessage = error ?? "Focused in Herdr. Switch to your Herdr terminal to continue."
                if error == nil { self.refresh() }
            }
        }
    }
}
