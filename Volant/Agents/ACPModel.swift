import AppKit
import Combine

/// UI-owned ACP conversation. Transcript stays in memory; the provider owns its own session storage.
final class ACPModel: ObservableObject {
    @Published var provider = "opencode"
    @Published var project = ""
    @Published var draft = ""
    @Published var state = ACPState()
    @Published var error: String?
    @Published var submitting = false
    private var connection: NSXPCConnection?
    private var timer: Timer?
    private var generation = UUID()
    private var reading = false
    private var revision = 0
    var active: Bool { !["failed", "disconnected"].contains(state.phase) }
    var canSend: Bool { state.phase == "ready" && !submitting && !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    func chooseProject() {
        PermissionGate.begin()
        let picker = NSOpenPanel()
        picker.canChooseDirectories = true; picker.canChooseFiles = false; picker.allowsMultipleSelection = false
        picker.prompt = "Use Project"
        if picker.runModal() == .OK, let url = picker.url { project = url.path }
        PermissionGate.end()
        NSApp.windows.first(where: { $0 is LauncherPanel })?.makeKeyAndOrderFront(nil)
    }
    func start() {
        disconnect()
        let current = generation
        state = ACPState(); state.phase = "starting"; state.status = "Connecting…"; error = nil
        let connection = NSXPCConnection(serviceName: "com.mysticcoders.volant.AgentHost")
        connection.remoteObjectInterface = NSXPCInterface(with: VolantAgentHostProtocol.self)
        connection.invalidationHandler = { [weak self] in DispatchQueue.main.async { self?.failed("Agent helper disconnected. Start a new conversation to reconnect.", current: current) } }
        connection.interruptionHandler = connection.invalidationHandler
        self.connection = connection; connection.resume()
        proxy()?.acpStart(provider: provider, project: project) { [weak self] error in
            DispatchQueue.main.async {
                guard let self, self.generation == current else { return }
                if let error { self.failed(error, current: current); return }
                self.read()
                self.timer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in self?.read() }
            }
        }
    }
    func send() {
        guard canSend else { return }
        let text = draft, current = generation
        revision += 1
        submitting = true; error = nil
        proxy()?.acpPrompt(text: text) { [weak self] error in
            DispatchQueue.main.async {
                guard let self, self.generation == current else { return }
                self.submitting = false
                if let error { self.error = error }
                else {
                    if self.draft == text { self.draft = "" }
                    // Keep Send disabled until a subsequent snapshot shows the completed turn.
                    self.state.phase = "working"
                }
                self.read()
            }
        }
    }
    func cancel() {
        let current = generation
        revision += 1
        state.phase = "cancelling"
        proxy()?.acpCancel { [weak self] error in DispatchQueue.main.async {
            guard let self, self.generation == current else { return }
            self.error = error; self.read()
        } }
    }
    func choose(_ permission: ACPPermission, _ option: ACPPermission.Option) {
        let current = generation
        revision += 1
        proxy()?.acpPermission(request: permission.id, option: option.optionId) { [weak self] error in DispatchQueue.main.async {
            guard let self, self.generation == current else { return }
            self.error = error; self.read()
        } }
    }
    func disconnect() {
        generation = UUID(); timer?.invalidate(); timer = nil; reading = false; submitting = false
        // Invalidation stops the provider even if it is waiting on a permission request.
        connection?.invalidate(); connection = nil
        state.phase = "disconnected"; state.status = "Conversation ended."; state.permissions = []; state.sessionID = nil
    }
    deinit { timer?.invalidate(); connection?.invalidate() }
    private func proxy() -> VolantAgentHostProtocol? {
        let current = generation
        return connection?.remoteObjectProxyWithErrorHandler { [weak self] error in
            DispatchQueue.main.async { self?.failed(error.localizedDescription, current: current) }
        } as? VolantAgentHostProtocol
    }
    private func read() {
        guard !reading, connection != nil else { return }
        reading = true
        let current = generation, currentRevision = revision
        proxy()?.acpRead { [weak self] data, error in DispatchQueue.main.async {
            guard let self, self.generation == current else { return }
            self.reading = false
            guard self.revision == currentRevision else { self.read(); return }
            guard let data, let snapshot = try? JSONDecoder().decode(ACPState.self, from: data) else {
                self.failed(error ?? "Invalid conversation state from helper.", current: current); return
            }
            if snapshot != self.state { self.state = snapshot }
            if snapshot.phase == "failed" { self.timer?.invalidate(); self.timer = nil }
        } }
    }
    private func failed(_ message: String, current: UUID) {
        guard generation == current else { return }
        disconnect(); state.phase = "failed"; error = message; state.status = message
    }
}
