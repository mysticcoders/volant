import AppKit
import Combine
import VolantCore

/// UI-owned ACP conversation. Transcript stays in memory; the provider owns its own session storage.
final class ACPModel: ObservableObject {
    @Published var provider = "opencode"
    @Published var project = ""
    @Published var draft = ""
    /// Owner-chosen context for the next prompt. Kept in memory with the draft, cleared once sent.
    @Published private(set) var attachments: [ChatAttachment] = []
    @Published var state = ACPState()
    @Published var error: String?
    @Published var submitting = false
    private var configuration = AIConfiguration()
    var credentials = AICredentials.keychain
    /// Apple's model runs in this process, so it uses neither helper.
    var usesApple: Bool { configuration.connection == .apple }
    var usesAPI: Bool { configuration.connection.usesHTTP }
    private var apple: AppleFoundationModel.Conversation?
    var providerTitle: String {
        if usesApple { return AIConnectionKind.apple.title }
        return usesAPI ? configuration.http.model : (ACPProvider(rawValue: provider)?.title ?? provider)
    }
    var configured: Bool {
        if usesApple { return AppleFoundationModel.availability.isReady }
        return usesAPI ? configuration.isConfigured : ACPProvider(rawValue: provider) != nil
    }

    func configure(_ value: AIConfiguration) {
        guard !active else { return }
        configuration = value
        provider = value.provider; project = value.connection == .acp ? value.project : ""
    }
    /// Reopening an active chat must never replace its session or draft.
    @discardableResult func openChat(configuration: AIConfiguration?, connect: () -> Void) -> Bool {
        if active { return true }
        guard let configuration, configuration.isConfigured else { return false }
        if configuration.connection == .byok {
            do { guard let key = try credentials.read(configuration.http.credentialID), !key.isEmpty else { return false } }
            catch { self.error = "Couldn’t read your API key. Open AI Settings to check it."; return false }
        }
        configure(configuration)
        connect()
        return true
    }
    private var connection: NSXPCConnection?
    private var timer: Timer?
    private var generation = UUID()
    private var reading = false
    private var revision = 0
    var active: Bool { !["failed", "disconnected"].contains(state.phase) }
    var canSend: Bool { state.phase == "ready" && !submitting && !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    func start() {
        disconnect()
        if usesApple { startApple(); return }
        if usesAPI { startAPI(); return }
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
    /// Adds a snapshot unless it is already attached; refuses one that would break the limits
    /// for this connection, leaving the draft and existing attachments unchanged.
    @discardableResult func attach(_ attachment: ChatAttachment) -> Bool {
        guard !attachments.contains(where: { $0.id == attachment.id }) else { return true }
        if let problem = ChatAttachmentLimits.problem(attachments + [attachment], apple: usesApple) {
            error = problem
            return false
        }
        attachments.append(attachment)
        error = nil
        return true
    }

    func detach(_ id: String) { attachments.removeAll { $0.id == id } }

    func send() {
        guard canSend else { return }
        let text = draft, sent = attachments, current = generation
        revision += 1
        submitting = true; error = nil
        let reply: (String?) -> Void = { [weak self] error in
            DispatchQueue.main.async {
                guard let self, self.generation == current else { return }
                self.submitting = false
                if let error { self.error = error }
                else {
                    if self.draft == text { self.draft = "" }
                    if self.attachments == sent { self.attachments = [] }
                    // Keep Send disabled until a subsequent snapshot shows the completed turn.
                    self.state.phase = "working"
                }
                if self.usesAPI { self.startAPIPolling() }
                self.read()
            }
        }
        if let problem = ChatAttachmentLimits.problem(sent, apple: usesApple) { submitting = false; error = problem; return }
        // Without attachments the original text-only path is used unchanged.
        guard !sent.isEmpty, let data = try? JSONEncoder().encode(sent) else {
            if usesApple { promptApple(text, reply: reply) }
            else if usesAPI { apiProxy()?.prompt(text: text, reply: reply) }
            else { proxy()?.acpPrompt(text: text, reply: reply) }
            return
        }
        if usesApple { promptApple(text, attachments: sent, reply: reply) }
        else if usesAPI { apiProxy()?.promptWithContext(text: text, attachments: data, reply: reply) }
        else { proxy()?.acpPromptWithContext(text: text, attachments: data, reply: reply) }
    }
    func cancel() {
        let current = generation
        revision += 1
        state.phase = "cancelling"
        let reply: (String?) -> Void = { [weak self] error in DispatchQueue.main.async {
            guard let self, self.generation == current else { return }
            self.error = error; self.read()
        } }
        if usesApple { apple?.cancel(); state.phase = "ready"; state.status = "Ready."; submitting = false }
        else if usesAPI { apiProxy()?.cancel { reply(nil) } }
        else { proxy()?.acpCancel(reply: reply) }
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
        apple?.cancel(); apple = nil
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
        let reply: (Data?, String?) -> Void = { [weak self] data, error in DispatchQueue.main.async {
            guard let self, self.generation == current else { return }
            self.reading = false
            guard self.revision == currentRevision else { self.read(); return }
            guard let data, let snapshot = try? JSONDecoder().decode(ACPState.self, from: data) else {
                self.failed(error ?? "Invalid conversation state from helper.", current: current); return
            }
            if snapshot != self.state { self.state = snapshot }
            if snapshot.phase == "failed" || (self.usesAPI && snapshot.phase == "ready") { self.timer?.invalidate(); self.timer = nil }
        } }
        if usesAPI { apiProxy()?.read(reply: reply) }
        else { proxy()?.acpRead(reply: reply) }
    }
    private func startAPI() {
        let current = generation
        do {
            let config = configuration.http
            try config.validate()
            let key = try credentials.read(config.credentialID) ?? ""
            if !config.local && key.isEmpty { throw AIHTTPError.key }
            state = ACPState(); state.phase = "starting"; state.status = "Connecting…"; error = nil
            let connection = NSXPCConnection(serviceName: "com.mysticcoders.volant.AIHost")
            connection.remoteObjectInterface = NSXPCInterface(with: VolantAIHostProtocol.self)
            connection.invalidationHandler = { [weak self] in DispatchQueue.main.async { self?.failed("AI connection ended. Connect again to start a new conversation.", current: current) } }
            connection.interruptionHandler = connection.invalidationHandler
            self.connection = connection; connection.resume()
            apiProxy()?.start(configuration: try JSONEncoder().encode(config), key: key) { [weak self] error in DispatchQueue.main.async {
                guard let self, self.generation == current else { return }
                if let error { self.failed(error, current: current); return }
                self.read()
                self.startAPIPolling()
            } }
            DispatchQueue.main.asyncAfter(deadline: .now() + 15) { [weak self] in
                guard let self, self.generation == current, self.state.phase == "starting" else { return }
                self.failed("AI helper did not become ready. Try connecting again.", current: current)
            }
        } catch { failed((error as? LocalizedError)?.errorDescription ?? "Couldn’t open AI connection.", current: current) }
    }
    /// Apple Intelligence runs in this process: no helper, no polling, no network. Availability is
    /// rechecked at connect time because the owner can switch it off in System Settings.
    private func startApple() {
        let availability = AppleFoundationModel.availability
        guard availability.isReady else {
            failed(availability.reason ?? "Apple Intelligence is unavailable.", current: generation)
            return
        }
        apple = AppleFoundationModel.Conversation()
        state = ACPState()
        state.phase = "ready"
        state.status = "Ready."
        state.agentName = AIConnectionKind.apple.title
        error = nil
    }

    private func promptApple(_ text: String, attachments: [ChatAttachment] = [], reply: @escaping (String?) -> Void) {
        let current = generation
        state.messages.append(ACPMessage(role: "You", text: text, attachments: attachments.isEmpty ? nil : attachments.map(\.title)))
        // The reply slot is created now and replaced as snapshots arrive, because FoundationModels
        // streams the whole text so far rather than deltas.
        let index = state.messages.count
        state.messages.append(ACPMessage(role: "Assistant", text: ""))
        reply(nil)
        apple?.send(ChatPromptComposer.inline(prompt: text, attachments: attachments), snapshot: { [weak self] snapshot in
            guard let self, self.generation == current, self.state.messages.indices.contains(index) else { return }
            self.state.messages[index] = ACPMessage(id: self.state.messages[index].id, role: "Assistant", text: snapshot)
        }, finished: { [weak self] failure in
            guard let self, self.generation == current else { return }
            self.submitting = false
            self.state.phase = "ready"
            self.state.status = failure ?? "Ready."
            if let failure { self.error = failure }
        })
    }

    private func startAPIPolling() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in self?.read() }
    }
    private func apiProxy() -> VolantAIHostProtocol? {
        let current = generation
        return connection?.remoteObjectProxyWithErrorHandler { [weak self] _ in DispatchQueue.main.async {
            self?.failed("AI helper disconnected. Connect again to start a new conversation.", current: current)
        } } as? VolantAIHostProtocol
    }
    private func failed(_ message: String, current: UUID) {
        guard generation == current else { return }
        disconnect(); state.phase = "failed"; error = message; state.status = message
    }
}
