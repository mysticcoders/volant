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
    /// Any change made here, rather than by a helper snapshot, forgets the helper's revision so
    /// the next read replaces it with the helper's full state.
    @Published var state = ACPState() { didSet { helperRevision = -1 } }
    /// The ACP helper revision `state` was last decoded from; -1 when none is current.
    private(set) var helperRevision = -1
    @Published var error: String?
    @Published var submitting = false
    /// The last ACP conversation, kept on this Mac only so it can be resumed by its own ID.
    @Published private(set) var resumable: ACPResumeRecord? {
        didSet { resumeWorkspaceGone = Self.workspaceMissing(resumable?.workspace) }
    }
    private let resumeStore: UserDefaults
    static let resumeKey = "acp.lastConversation"
    /// Whether the next new conversation runs in its own git worktree of `project`.
    @Published var isolate = false
    /// The git worktree this conversation runs in, kept after it ends so it can be removed. Set by
    /// `connect` and removal; fixtures set it directly.
    @Published var workspace: String?
    /// The workspace's branch and change counts, read when the conversation becomes ready and after
    /// each turn.
    @Published var workspaceState: RepositoryState?
    @Published private(set) var removingWorkspace = false
    /// Read when the record or the conversation changes rather than on every redraw, since each
    /// read the sandbox refuses is also logged.
    private var resumeWorkspaceGone = false

    init(resumeStore: UserDefaults = .standard) {
        self.resumeStore = resumeStore
        resumable = Self.record(in: resumeStore)
        resumeWorkspaceGone = Self.workspaceMissing(resumable?.workspace)
    }
    /// The stored record, read again each time: another conversation may have replaced it.
    private static func record(in store: UserDefaults) -> ACPResumeRecord? {
        guard let data = store.data(forKey: resumeKey),
              let record = try? JSONDecoder().decode(ACPResumeRecord.self, from: data), record.isValid else { return nil }
        return record
    }
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
        isolate = value.connection == .acp && !value.project.isEmpty && value.isolate
    }
    /// Reopening an active chat must never replace its session or draft. A conversation that can be
    /// resumed is offered instead of connecting, so opening the chat never replaces its record, and
    /// one that kept a workspace is shown as it is, so Remove Workspace stays within reach.
    @discardableResult func openChat(configuration: AIConfiguration?, connect: () -> Void) -> Bool {
        if active { return true }
        guard let configuration, configuration.isConfigured, keyReady(for: configuration) else { return false }
        configure(configuration)
        if !canResume, workspace == nil { connect() }
        return true
    }
    /// False for a BYOK connection without a stored key, so the caller opens AI Settings instead of
    /// starting a conversation that fails; a key that can't be read is reported in `error`.
    func keyReady(for configuration: AIConfiguration) -> Bool {
        guard configuration.connection == .byok else { return true }
        do { guard let key = try credentials.read(configuration.http.credentialID), !key.isEmpty else { return false } }
        catch { self.error = "Couldn’t read your API key. Open AI Settings to check it."; return false }
        return true
    }
    private var connection: NSXPCConnection?
    private var timer: Timer?
    private var generation = UUID()
    private var reading = false
    private var revision = 0
    /// Set on every conversation except the one AI Chat shows. While an agent streams, each poll
    /// decodes the whole transcript on the main thread, and six conversations polling every 0.25 s
    /// would decode up to 24 transcripts a second, so a conversation in the background polls once a
    /// second.
    var background = false {
        didSet { if background != oldValue, timer != nil { schedulePolling() } }
    }
    /// Seconds between snapshot reads.
    var pollInterval: TimeInterval { background ? 1 : 0.25 }
    /// The recorded session ID this conversation asked the agent to load. Several conversations
    /// share one record, so a refused load clears it only while it still names this session.
    var resumedSession: String?
    /// Native session IDs that the launcher's other live conversations hold. Resume never loads one
    /// of them, so one session never runs in two agent processes.
    var sessionsElsewhere: () -> [String] = { [] }
    /// Called with a session ID that can no longer resume: the agent refused to load it, or its
    /// workspace was removed. Every conversation read the record when it was made, so the launcher
    /// tells the others to stop offering that session too.
    var resumeRefused: (String) -> Void = { _ in }
    func forgetResume(of session: String) {
        if resumable?.sessionID == session { resumable = nil }
    }
    /// The start of the owner's first message, which tells apart conversations started with the same
    /// provider and folder; nil before the first turn.
    var topic: String? {
        guard let text = state.messages.first(where: { $0.role == "You" })?.text.trimmingCharacters(in: .whitespacesAndNewlines),
              let line = text.split(whereSeparator: \.isNewline).first else { return nil }
        return line.count > 24 ? String(line.prefix(23)) + "…" : String(line)
    }
    var active: Bool { !["failed", "disconnected"].contains(state.phase) }
    /// Resume is offered only for the provider and project currently chosen, so it can never
    /// reopen a conversation in a folder the owner has since moved away from, and not once its
    /// workspace is known to be gone or while it is being removed.
    var canResume: Bool {
        guard !active, !usesAPI, !usesApple, let record = resumable, record.matches(provider: provider, project: project),
              !resumeWorkspaceGone, !removingWorkspace else { return false }
        return !sessionsElsewhere().contains(record.sessionID)
    }
    /// Whether a recorded workspace is known to be gone. The sandboxed app may be refused even a look
    /// at the helper's folder; that answer (EPERM) is unknown rather than missing, so Resume stays
    /// offered and the helper reports a missing folder if there is one.
    static func workspaceMissing(_ path: String?) -> Bool {
        guard let path else { return false }
        var info = stat()
        if stat(path, &info) == 0 { return info.st_mode & S_IFMT != S_IFDIR }
        return errno == ENOENT || errno == ENOTDIR
    }
    /// What `connect` asks the helper for. A resume runs in the folder the conversation ran in, since
    /// an agent may keep its sessions by working folder, as Claude Code does.
    enum HelperStart: Equatable {
        case start(project: String)
        case isolated(project: String)
        case resume(folder: String, session: String)
    }
    func helperStart(resume record: ACPResumeRecord?) -> HelperStart {
        if let record { return .resume(folder: record.workspace ?? project, session: record.sessionID) }
        return isolate ? .isolated(project: project) : .start(project: project)
    }
    var canSend: Bool { state.phase == "ready" && !submitting && !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    /// Does nothing while this conversation's workspace is being removed, since the removal reports
    /// its result here.
    func start() {
        guard !removingWorkspace else { return }
        resumedSession = nil
        connect(resume: nil)
    }

    func resume() {
        guard canResume, let record = resumable else { return }
        resumedSession = record.sessionID
        connect(resume: record)
    }

    private func connect(resume record: ACPResumeRecord?) {
        disconnect()
        workspace = record?.workspace; workspaceState = nil
        if usesApple { startApple(); return }
        if usesAPI { startAPI(); return }
        let current = generation, request = helperStart(resume: record)
        state = ACPState(); state.phase = "starting"; error = nil
        switch request {
        case .start: state.status = "Connecting…"
        case .isolated: state.status = "Creating workspace…"
        case .resume: state.status = "Restoring conversation…"
        }
        let connection = NSXPCConnection(serviceName: "com.mysticcoders.volant.AgentHost")
        connection.remoteObjectInterface = NSXPCInterface(with: VolantAgentHostProtocol.self)
        connection.invalidationHandler = { [weak self] in DispatchQueue.main.async { self?.failed("Agent helper disconnected. Start a new conversation to reconnect.", current: current) } }
        connection.interruptionHandler = connection.invalidationHandler
        self.connection = connection; connection.resume()
        let started: (String?) -> Void = { [weak self] error in
            DispatchQueue.main.async {
                guard let self, self.generation == current else { return }
                if let error { self.failed(error, current: current); return }
                self.read()
                self.schedulePolling()
            }
        }
        switch request {
        case .start(let folder): proxy()?.acpStart(provider: provider, project: folder, reply: started)
        case .resume(let folder, let session): proxy()?.acpResume(provider: provider, project: folder, session: session, reply: started)
        case .isolated(let folder):
            // A workspace made before a failed start is kept, so it is recorded either way.
            proxy()?.acpStartIsolated(provider: provider, project: folder) { [weak self] path, error in
                DispatchQueue.main.async { if let self, self.generation == current, let path { self.workspace = path } }
                started(error)
            }
        }
    }
    /// Records a conversation once it is ready and holds an owner turn, so a session opened and left
    /// unused never replaces the record. A launch failure keeps the record, since the cause may be an
    /// expired provider login with the conversation still intact; an agent that refuses to load it
    /// clears it, unless another conversation has recorded its own since, and no conversation offers
    /// that session again.
    func remember(_ snapshot: ACPState) {
        if snapshot.resumeRejected == true {
            if let rejected = resumedSession {
                if Self.record(in: resumeStore)?.sessionID == rejected { resumeStore.removeObject(forKey: Self.resumeKey) }
                resumeRefused(rejected)
            }
            resumable = nil; return
        }
        guard !usesAPI, !usesApple, snapshot.phase == "ready", let session = snapshot.sessionID,
              snapshot.messages.contains(where: { $0.role == "You" }) else { return }
        let record = ACPResumeRecord(provider: provider, project: project, sessionID: session, workspace: workspace)
        guard record.isValid, resumable?.sessionID != session || resumable?.matches(provider: provider, project: project) != true,
              let data = try? JSONEncoder().encode(record) else { return }
        resumeStore.set(data, forKey: Self.resumeKey)
        resumable = record
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
        resumeWorkspaceGone = Self.workspaceMissing(resumable?.workspace)
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
        let current = generation, currentRevision = revision, known = usesAPI ? -1 : helperRevision
        let reply: (Data?, Int, String?) -> Void = { [weak self] data, snapshotRevision, error in DispatchQueue.main.async {
            guard let self, self.generation == current else { return }
            self.reading = false
            guard self.revision == currentRevision else { self.read(); return }
            let before = self.state.phase
            switch self.receive(data, revision: snapshotRevision, after: known) {
            case .unchanged: return
            case .stale: self.read(); return
            case .invalid: self.failed(error ?? "Invalid conversation state from helper.", current: current); return
            case .applied: break
            }
            if Self.turnEnded(from: before, to: self.state.phase) { self.refreshWorkspace() }
            if self.state.phase == "failed" || (self.usesAPI && self.state.phase == "ready") { self.timer?.invalidate(); self.timer = nil }
        } }
        if usesAPI { apiProxy()?.read { reply($0, -1, $1) } }
        else { proxy()?.acpRead(after: known, reply: reply) }
    }
    enum SnapshotResult { case applied, unchanged, stale, invalid }
    /// Applies one helper reply to a read that asked for changes after `known`. A reply without
    /// data confirms `known` is current, so nothing is decoded; if the app changed `state` while
    /// that read was in flight, the reply is stale and the next read fetches the full state.
    /// Otherwise the snapshot replaces `state` only when it differs, and its revision is kept.
    func receive(_ data: Data?, revision: Int, after known: Int) -> SnapshotResult {
        if data == nil, revision >= 0, revision == known { return helperRevision == known ? .unchanged : .stale }
        guard let data, let snapshot = try? JSONDecoder().decode(ACPState.self, from: data) else { return .invalid }
        if snapshot != state { state = snapshot }
        helperRevision = revision
        remember(snapshot)
        return .applied
    }
    /// True when the conversation becomes ready or a turn ends.
    static func turnEnded(from old: String, to new: String) -> Bool {
        new == "ready" && ["starting", "working", "cancelling"].contains(old)
    }
    /// Reads the workspace's branch and change counts through this conversation's own connection.
    private func refreshWorkspace() {
        guard let workspace, let paths = try? JSONEncoder().encode([workspace]) else { return }
        let current = generation
        proxy()?.repositoryStates(paths: paths) { [weak self] data, _ in
            let states = data.flatMap { try? JSONDecoder().decode([String: RepositoryState].self, from: $0) }
            DispatchQueue.main.async {
                guard let self, self.generation == current, self.workspace == workspace, let states else { return }
                self.workspaceState = states[workspace]
            }
        }
    }
    var canRemoveWorkspace: Bool { !active && workspace != nil && !removingWorkspace }
    /// Replaced in tests, so they never open a helper connection.
    var worktreeRemover: (String, @escaping (String?, String?) -> Void) -> Void = ACPModel.removeWorktree
    /// Removes the ended conversation's workspace. The helper refuses one with any change, and its
    /// branch stays either way. The reply holds the model even if the conversation list drops it, so
    /// the record is still cleared.
    func removeWorkspace() {
        guard canRemoveWorkspace, let path = workspace else { return }
        removingWorkspace = true; error = nil; state.status = "Removing workspace…"
        worktreeRemover(path) { branch, error in
            DispatchQueue.main.async { self.workspaceRemoved(path, branch: branch, error: error) }
        }
    }
    /// The helper replies with the kept branch, with an error, or with neither when no folder was left
    /// at the path. Once the workspace is gone, a conversation that ran in it can no longer resume, so
    /// its record is cleared here and in every other conversation.
    func workspaceRemoved(_ path: String, branch: String?, error: String?) {
        removingWorkspace = false
        let shown = workspace == path && !active
        if let error {
            if shown { self.error = error; state.status = "Workspace kept." }
            return
        }
        var sessions = Set<String>()
        if let stored = Self.record(in: resumeStore), stored.workspace == path {
            resumeStore.removeObject(forKey: Self.resumeKey); sessions.insert(stored.sessionID)
        }
        if let record = resumable, record.workspace == path { resumable = nil; sessions.insert(record.sessionID) }
        sessions.forEach(resumeRefused)
        guard shown else { return }
        workspace = nil; workspaceState = nil
        state.status = branch.map { "Removed the workspace. Its branch \($0) keeps its commits." } ?? "The workspace’s folder was already gone."
    }
    /// The conversation's own connection closed when it ended, so removal opens one of its own.
    private static func removeWorktree(_ path: String, reply: @escaping (String?, String?) -> Void) {
        let connection = NSXPCConnection(serviceName: "com.mysticcoders.volant.AgentHost")
        connection.remoteObjectInterface = NSXPCInterface(with: VolantAgentHostProtocol.self)
        connection.resume()
        let failed = "Agent helper disconnected. Try again."
        guard let proxy = connection.remoteObjectProxyWithErrorHandler({ _ in connection.invalidate(); reply(nil, failed) }) as? VolantAgentHostProtocol else {
            connection.invalidate(); reply(nil, failed); return
        }
        proxy.removeWorktree(path: path) { branch, error in connection.invalidate(); reply(branch, error) }
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

    private func startAPIPolling() { schedulePolling() }
    /// Replaces the snapshot timer with one at this conversation's interval.
    private func schedulePolling() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: pollInterval, repeats: true) { [weak self] _ in self?.read() }
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
