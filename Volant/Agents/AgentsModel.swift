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
        attentionRequest = UUID()
        attentionTarget = session
        attention = nil; attentionError = nil; attentionLoading = false
        refreshAttention()
    }

    func refreshAttention() {
        guard let target = attentionTarget else { return }
        guard connected, HerdrAttention.matches(target, in: sessions) else {
            attentionRequest = UUID(); attention = nil; attentionError = nil; attentionLoading = false
            return
        }
        guard !attentionLoading else { return }
        let request = UUID(); attentionRequest = request
        attentionLoading = true
        let completion: (Data?, String?) -> Void = { [weak self] data, error in
            DispatchQueue.main.async {
                guard let self, self.attentionRequest == request, self.connected,
                      HerdrAttention.matches(target, in: self.sessions) else { return }
                self.attentionLoading = false
                self.attention = data.flatMap { try? HerdrAttention.preview($0) }
                self.attentionError = error ?? (self.attention == nil ? "Couldn’t read this question. Open it in Herdr." : nil)
            }
        }
        if let attentionReader { attentionReader(target, completion); return }
        guard let connection else { completion(nil, "Herdr is disconnected."); return }
        let proxy = connection.remoteObjectProxyWithErrorHandler { _ in completion(nil, "Couldn’t read this question. Open it in Herdr.") } as? VolantAgentHostProtocol
        proxy?.readAgentAttention(paneID: target.paneID, terminalID: target.terminalID, sessionIdentity: target.sessionIdentity, reply: completion)
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
