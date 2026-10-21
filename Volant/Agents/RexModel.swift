import AppKit
import SwiftUI
import VolantCore

/// Rex panes for the `rex` view and footer status. UI-owned; callbacks are delivered on the main
/// queue. While connected it keeps one read outstanding with the agent helper's Rex watcher, which
/// holds it until something newer than the revision it names, so a change arrives as soon as the
/// watcher prints it; each reply starts the next read. A one-second timer only restarts reading if
/// a read fails to come back. A reply that arrives after a disconnect, or behind a newer request,
/// is dropped.
final class RexModel: ObservableObject {
    @Published private(set) var panes: [RexPane] = []
    @Published private(set) var connected = false
    @Published private(set) var loading = false
    /// Why the last read failed, such as Rex not running. Cleared by the next successful read.
    @Published private(set) var problem: String?
    @Published private(set) var unreadableSessions = 0
    /// Injected only by isolated tests; production reads and focuses through the signed helper.
    var reader: ((Int, @escaping (Data?, Int, String?) -> Void) -> Void)?
    var stopper: (() -> Void)?
    var focuser: ((RexPane, @escaping (String?) -> Void) -> Void)?
    var activateRex: () -> Void = RexModel.activateRexApp
    private var connection: NSXPCConnection?
    private var timer: Timer?
    private var generation = 0
    private var request: UUID?
    private var revision = -1
    private var focusInFlight = false

    var message: String {
        if let problem { return problem }
        if loading && panes.isEmpty { return "Loading Rex panes…" }
        return panes.isEmpty ? "No Rex panes are open." : "Rex panes · refreshes automatically"
    }

    /// Starts reading, which starts the helper's watcher. Volant only reads local status here, so it
    /// begins as soon as the `rex` view or footer status is shown, with no Connect step.
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
        loading = true
        refresh()
        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in Task { @MainActor in self?.refresh() } }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    /// Stops the helper's watcher before letting the connection go; the helper also stops it when
    /// the connection ends or reads stop arriving.
    func disconnect() {
        generation += 1
        timer?.invalidate(); timer = nil
        if connected {
            if let stopper { stopper() }
            else { proxy(reply: { _ in })?.stopRexPanes {} }
        }
        connection?.invalidate(); connection = nil
        request = nil; focusInFlight = false; revision = -1
        update(\.connected, false); update(\.loading, false)
        update(\.panes, []); update(\.problem, nil); update(\.unreadableSessions, 0)
    }

    private func failed(_ message: String, generation current: Int) {
        guard current == generation else { return }
        disconnect()
        problem = message
    }

    /// One read at a time; a tick that finds a read outstanding does nothing. A reply at the
    /// revision already held changes nothing. A newer one with no panes and no message means the
    /// watcher is still starting.
    func refresh() {
        guard connected, request == nil else { return }
        let token = UUID(), current = generation, known = revision
        request = token
        let reply: (Data?, Int, String?) -> Void = { [weak self] data, latest, error in
            let inventory = data.flatMap { try? JSONDecoder().decode(RexInventory.self, from: $0) }
            DispatchQueue.main.async {
                guard let self, self.connected, current == self.generation, self.request == token else { return }
                self.request = nil
                defer { self.refresh() }
                guard latest != known else { return }
                self.revision = latest
                if let inventory {
                    self.update(\.panes, inventory.panes)
                    self.update(\.unreadableSessions, inventory.unreadableSessions)
                    self.update(\.problem, nil)
                    self.update(\.loading, false)
                } else {
                    self.update(\.panes, [])
                    self.update(\.problem, error ?? (data == nil ? nil : "Couldn’t read Rex panes."))
                    self.update(\.loading, error == nil && data == nil)
                }
            }
        }
        if let reader { reader(known, reply) }
        else { proxy(reply: { reply(nil, known + 1, $0) })?.readRexPanes(after: known, reply: reply) }
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

    /// Hands activation to Rex, which macOS requires before another app can come forward. The
    /// launcher panel does not make Volant the active app, so when Rex refuses the handoff, opening
    /// Rex through Launch Services brings it forward instead.
    private static func activateRexApp() {
        if let app = NSRunningApplication.runningApplications(withBundleIdentifier: RexScript.appBundleIdentifier).first {
            NSApp.yieldActivation(to: app)
            if app.activate() { return }
        }
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: RexScript.appBundleIdentifier) else { return }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        NSWorkspace.shared.openApplication(at: url, configuration: configuration)
    }
}
