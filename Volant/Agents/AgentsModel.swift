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
                    self.message = self.sessions.isEmpty ? "No agents are running in the default Herdr session." : "Local Herdr · updates every 5 seconds"
                } catch { self.failed("Herdr returned an unsupported response.", generation: current) }
            }
        }
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
