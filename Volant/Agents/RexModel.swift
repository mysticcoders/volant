import AppKit
import SwiftUI
import VolantCore

/// Rex panes for the `rex` view and footer status. UI-owned; callbacks are delivered on the main
/// queue. It reads through the agent helper every five seconds while connected, and a reply that
/// arrives after a disconnect, or behind a newer request, is dropped.
final class RexModel: ObservableObject {
    @Published private(set) var panes: [RexPane] = []
    @Published private(set) var connected = false
    @Published private(set) var loading = false
    /// Why the last read failed, such as Rex not running. Cleared by the next successful read.
    @Published private(set) var problem: String?
    @Published private(set) var unreadableSessions = 0
    /// Injected only by isolated tests; production reads and focuses through the signed helper.
    var reader: ((@escaping (Data?, String?) -> Void) -> Void)?
    var focuser: ((RexPane, @escaping (String?) -> Void) -> Void)?
    var activateRex: () -> Void = RexModel.activateRexApp
    private var connection: NSXPCConnection?
    private var timer: Timer?
    private var generation = 0
    private var request: UUID?
    private var focusInFlight = false

    var message: String {
        if let problem { return problem }
        if loading && panes.isEmpty { return "Loading Rex panes…" }
        return panes.isEmpty ? "No Rex panes are open." : "Rex panes · refreshes automatically"
    }

    /// Starts reading. Volant only reads local status here, so it begins as soon as the `rex` view
    /// or footer status is shown, with no Connect step.
    func connect() {
        guard !connected else { return }
        generation += 1
        if reader == nil {
            let connection = NSXPCConnection(serviceName: "com.mysticcoders.volant.AgentHost")
            connection.remoteObjectInterface = NSXPCInterface(with: VolantAgentHostProtocol.self)
            let current = generation
            connection.interruptionHandler = { [weak self] in DispatchQueue.main.async { self?.failed("The agent helper disconnected.", generation: current) } }
            connection.invalidationHandler = { [weak self] in DispatchQueue.main.async { self?.failed("The agent helper is unavailable.", generation: current) } }
            self.connection = connection
            connection.resume()
        }
        connected = true
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in Task { @MainActor in self?.refresh() } }
    }

    func disconnect() {
        generation += 1
        timer?.invalidate(); timer = nil
        connection?.invalidate(); connection = nil
        request = nil; focusInFlight = false
        update(\.connected, false); update(\.loading, false)
        update(\.panes, []); update(\.problem, nil); update(\.unreadableSessions, 0)
    }

    private func failed(_ message: String, generation current: Int) {
        guard current == generation else { return }
        disconnect()
        problem = message
    }

    /// One read at a time; a tick that finds a read outstanding waits for the next tick.
    func refresh() {
        guard connected, request == nil else { return }
        let token = UUID(), current = generation
        request = token
        update(\.loading, true)
        let reply: (Data?, String?) -> Void = { [weak self] data, error in
            let inventory = error == nil ? data.flatMap { try? JSONDecoder().decode(RexInventory.self, from: $0) } : nil
            DispatchQueue.main.async {
                guard let self, self.connected, current == self.generation, self.request == token else { return }
                self.request = nil
                self.update(\.loading, false)
                if let inventory {
                    self.update(\.panes, inventory.panes)
                    self.update(\.unreadableSessions, inventory.unreadableSessions)
                    self.update(\.problem, nil)
                } else {
                    self.update(\.panes, [])
                    self.update(\.problem, error ?? "Couldn’t read Rex panes.")
                }
            }
        }
        if let reader { reader(reply) }
        else { proxy(reply: { reply(nil, $0) })?.listRexPanes(reply: reply) }
    }

    /// Focuses a pane that is still listed, then brings Rex forward. The helper checks the pane
    /// again inside Rex before focusing, so a pane closed since this list was read is refused.
    func focus(_ pane: RexPane, completion: @escaping (String?) -> Void) {
        guard connected, !focusInFlight, panes.contains(where: { $0.id == pane.id }) else {
            completion(connected ? "This pane changed or closed. Refresh before continuing." : message); return
        }
        focusInFlight = true
        let current = generation
        let done: (String?) -> Void = { [weak self] error in
            DispatchQueue.main.async {
                guard let self, current == self.generation else { return }
                self.focusInFlight = false
                if error == nil { self.activateRex() } else { self.refresh() }
                completion(error)
            }
        }
        if let focuser { focuser(pane, done) }
        else { proxy(reply: done)?.focusRexPane(session: pane.sessionID, block: pane.blockID, reply: done) }
    }

    private func proxy(reply: @escaping (String) -> Void) -> VolantAgentHostProtocol? {
        connection?.remoteObjectProxyWithErrorHandler { _ in reply("The agent helper is unavailable.") } as? VolantAgentHostProtocol
    }

    /// Assigns only real changes, so a five-second refresh that changes nothing redraws nothing.
    private func update<Value: Equatable>(_ keyPath: ReferenceWritableKeyPath<RexModel, Value>, _ value: Value) {
        if self[keyPath: keyPath] != value { self[keyPath: keyPath] = value }
    }

    /// Hands activation to Rex, which macOS requires before another app can come forward.
    private static func activateRexApp() {
        guard let app = NSRunningApplication.runningApplications(withBundleIdentifier: RexScript.appBundleIdentifier).first else { return }
        NSApp.yieldActivation(to: app)
        app.activate()
    }
}
