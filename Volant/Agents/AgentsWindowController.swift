import AppKit
import SwiftUI

@MainActor final class AgentsModel: ObservableObject {
    @Published var sessions: [AgentSession] = []
    @Published var connected = false
    @Published var busy = false
    @Published var message = "Connect to the default local Herdr session to see your running agents."
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
        connected = false; busy = false; sessions = []
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
                self.message = error ?? "Focused in Herdr. Switch to your Herdr terminal to continue."
                if error == nil { self.refresh() }
            }
        }
    }
}

struct AgentsView: View {
    @ObservedObject var model: AgentsModel
    @State private var selection: String?
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Your agents").font(.title2.weight(.semibold))
                    Text("Herdr sessions, close at hand.").foregroundStyle(.secondary)
                }
                Spacer()
                if model.busy { ProgressView().controlSize(.small) }
                Button(model.connected ? "Disconnect" : "Connect Herdr") {
                    if model.connected { model.disconnect() } else { model.connect() }
                }
            }
            TextField("Search projects, agents, or status", text: $model.query)
                .textFieldStyle(.roundedBorder)
                .accessibilityLabel("Search agent sessions")
            List(selection: $selection) {
                ForEach(model.filtered) { session in
                    HStack(spacing: 12) {
                        Image(systemName: session.agentStatus == "blocked" ? "exclamationmark.bubble" : "terminal")
                            .foregroundStyle(session.agentStatus == "blocked" ? Color.orange : Color.secondary)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(session.project).fontWeight(.medium)
                            Text(session.provider + " · " + session.paneID).font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text(session.status).font(.caption).foregroundStyle(.secondary)
                        Button("Focus") { model.focus(session) }.disabled(model.busy)
                            .accessibilityLabel("Focus \(session.provider) in \(session.project)")
                    }.padding(.vertical, 5).tag(session.id)
                }
            }
            .overlay {
                if model.filtered.isEmpty {
                    Text(model.sessions.isEmpty ? model.message : "No matching sessions.")
                        .foregroundStyle(.secondary).multilineTextAlignment(.center).padding(28)
                }
            }
            HStack {
                Text(model.message).font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("Refresh") { model.refresh() }.disabled(!model.connected || model.busy)
                    .keyboardShortcut("r", modifiers: .command)
            }
            Divider()
            Text("Native conversations and approvals through ACP and provider adapters are in development. Connecting here lists session metadata; it does not send prompts or share your notes.")
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
        .padding(24)
        .frame(minWidth: 580, minHeight: 420)
        .background(Color(nsColor: .windowBackgroundColor))
        .onSubmit {
            if let session = model.filtered.first(where: { $0.id == selection }) { model.focus(session) }
        }
    }
}

final class AgentsWindowController: NSWindowController, NSWindowDelegate {
    let model = AgentsModel()
    init() {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 700, height: 520), styleMask: [.titled, .closable, .resizable, .miniaturizable], backing: .buffered, defer: false)
        window.title = "Volant Agents"
        window.isReleasedWhenClosed = false
        super.init(window: window)
        window.contentView = NSHostingView(rootView: AgentsView(model: model))
        window.delegate = self
        window.setFrameAutosaveName("VolantAgents")
        window.center()
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    func windowWillClose(_ notification: Notification) { model.disconnect() }
}
