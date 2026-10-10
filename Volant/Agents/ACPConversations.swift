import Combine
import Foundation
import VolantCore

/// Conversations are told apart by object, so a button always acts on the conversation it was
/// drawn for, never on a position in a list.
extension ACPModel: Identifiable {}

/// The launcher's AI conversations. One is current and shown; the others keep running in
/// their own helper connections until the owner ends them.
final class ACPConversations: ObservableObject {
    /// Every conversation in creation order, including ended ones not yet dropped.
    @Published private(set) var all: [ACPModel] {
        didSet { watchPhases(); updateBackground() }
    }
    @Published private(set) var current: ACPModel {
        didSet { followCurrent(); updateBackground() }
    }
    /// Whether AI Chat is on screen in the open launcher. Set by the launcher; only then is the
    /// current conversation shown, so only then does the end of its turn leave it read.
    var chatShown = false {
        didSet { if chatShown != oldValue { updateBackground() } }
    }
    /// Send to Several conversations that wait for a live slot, in the order they start. They join
    /// `all` when they start.
    @Published private(set) var waiting: [ACPModel] = []
    private let make: () -> ACPModel
    private let start: (ACPModel) -> Void
    private var currentChanges: AnyCancellable?
    private var phaseChanges: AnyCancellable?
    /// Set after the helper refused a start at its limit, so no waiting conversation starts until the
    /// retry runs.
    private var holding = false
    /// The next `queuePosition` Send to Several gives a conversation.
    private var queued = 0
    /// How often a waiting conversation the helper refused at its limit is tried again after a second.
    static let retryLimit = 3
    /// Seconds between later tries. The helper can keep the slot of a conversation the app has ended
    /// until it finishes making that conversation's workspace, and each git call in that may take
    /// up to 120 s.
    static let slowRetry: TimeInterval = 30
    /// Runs a retry after the given seconds, once the helper refused a start at its limit. Replaced in
    /// tests.
    var retryLater: (TimeInterval, @escaping () -> Void) -> Void = { DispatchQueue.main.asyncAfter(deadline: .now() + $0, execute: $1) }
    /// The Send to Several whose checks are out. Closing the picker cancels it, so a check that
    /// replies afterwards starts nothing and leaves the draft as it is.
    private var pendingSend: UUID?
    /// Asks the helper whether a workspace could be made of a folder, replying with the reason when
    /// it couldn't. Replaced in tests, so they never open a helper connection.
    var worktreeChecker: (String, @escaping (String?) -> Void) -> Void = ACPConversations.checkWorktree
    /// Asks the helper whether a provider could start under an account folder, replying with the
    /// reason when it couldn't. Replaced in tests, so they never open a helper connection.
    var accountChecker: (String, String, @escaping (String?) -> Void) -> Void = ACPConversations.checkAccount

    /// `start` is injected so tests never open an XPC connection.
    init(make: @escaping () -> ACPModel = { ACPModel() }, start: @escaping (ACPModel) -> Void = { $0.start() }) {
        let first = make()
        self.make = make
        self.start = start
        all = [first]
        current = first
        adopt(first)
        followCurrent()
        watchPhases()
        updateBackground()
    }

    /// Conversations with a running session.
    var live: [ACPModel] { all.filter(\.active) }
    /// What the conversation buttons list: the kept conversations, plus the current one after it
    /// ends, in the order they were started.
    var shown: [ACPModel] { all.filter { Self.kept($0) || $0 === current } }
    /// What the launcher's row lists: the live conversations and the ended ones not yet read.
    var listed: [ACPModel] { all.filter { $0.active || $0.unread } }
    /// The app counts a conversation as ended as soon as End runs. The helper frees its slot when that
    /// connection's invalidation reaches it, unordered with a start on another connection, so a start
    /// sent within that delivery delay can still be refused at the limit.
    var canStartAnother: Bool { live.count < ACPConversationLimit.live }
    /// The conversation the launcher opens: the first that waits for a permission, else the current
    /// one while it runs, else the first that runs, else the first unread one. Opening AI Chat on an
    /// ended conversation can start a new one in its place, so the row opens a running one first.
    var nextToOpen: ACPModel {
        live.first { !$0.state.permissions.isEmpty } ?? (current.active ? current : live.first ?? all.first(where: \.unread) ?? current)
    }

    /// Starts a conversation with `configuration` and shows it, leaving the others running. An unused
    /// current conversation without a workspace is started in place. Returns false and starts
    /// nothing when the configuration is missing or incomplete, or when the live limit is reached;
    /// the limit is reported in the current conversation.
    @discardableResult func newConversation(configuration: AIConfiguration?) -> Bool {
        guard let configuration, configuration.isConfigured else { return false }
        guard canStartAnother else {
            current.error = ACPConversationLimit.refusal()
            return false
        }
        // One that kept a workspace is not started in place: while its removal runs, start does nothing.
        // Neither is a Send to Several conversation, which keeps its agent and its result.
        if !current.active, current.state.messages.isEmpty, current.workspace == nil, !current.fanOutTarget {
            current.configure(configuration)
            start(current)
            return true
        }
        let model = make()
        adopt(model)
        model.configure(configuration)
        all.append(model)
        current = model
        dropEnded()
        start(model)
        return true
    }

    /// Applies saved AI settings. The current conversation takes them through `configure` unless it
    /// runs or is a Send to Several conversation, and the next start of every ACP conversation but a
    /// Send to Several one follows the account now chosen for its provider.
    func apply(_ configuration: AIConfiguration) {
        current.configure(configuration)
        all.forEach { $0.followAccountChoice(configuration) }
    }

    func select(_ model: ACPModel) {
        guard all.contains(where: { $0 === model }) else { return }
        current = model
        dropEnded()
    }

    /// Drops every conversation that is neither kept nor current; its transcript was in memory only.
    private func dropEnded() {
        let current = self.current
        all.removeAll { !Self.kept($0) && $0 !== current }
    }

    /// Live and unread conversations stay listed, and so does a Send to Several conversation that
    /// still has its workspace: one send can leave six, and Remove Workspace is reached through the
    /// conversation that made it.
    private static func kept(_ model: ACPModel) -> Bool {
        model.active || model.unread || (model.fanOutTarget && model.workspace != nil)
    }

    /// Send to Several: one new conversation per target, each sending `prompt` with copies of
    /// `attachments` once it is first ready. Targets past the live limit wait and start in order as
    /// conversations end. Unless `headless`, the first one that starts is shown. Each runs under the
    /// account chosen for its own provider. Returns the new conversations in target order.
    @discardableResult func fanOut(prompt: String, attachments: [ChatAttachment], targets: [AIConfiguration], headless: Bool) -> [ACPModel] {
        let pending = ACPModel.PendingPrompt(text: prompt, attachments: attachments)
        let models = targets.map { target -> ACPModel in
            let model = make()
            adopt(model)
            model.configure(target)
            model.assign(pending, headless: headless)
            model.queuePosition = queued
            queued += 1
            return model
        }
        waiting += models
        startWaiting()
        if !headless, let first = models.first(where: { model in all.contains { $0 === model } }) {
            current = first
            dropEnded()
        }
        return models
    }

    /// Drops the conversations still waiting; the ones that started keep running.
    func cancelWaiting() {
        let dropped = waiting
        waiting = []
        dropped.forEach { $0.dropPendingPrompt() }
    }

    /// Plans Send to Several from `source`'s draft and attachments, checks the account folders and
    /// the folder, starts the targets and clears what was copied from `source`'s composer. Replies
    /// on the main queue with the reason when nothing started, else with nil; a send canceled during
    /// its checks never replies. One send checks at a time.
    func sendToSeveral(from source: ACPModel, settings: AIConfiguration, counts: [ACPProvider: Int], headless: Bool,
                       done: @escaping (String?) -> Void) {
        guard pendingSend == nil else { done("Send to Several is still checking the folder."); return }
        let text = source.draft, sent = source.attachments
        let targets: [AIConfiguration]
        do { targets = try ACPFanOut.targets(prompt: text, counts: counts, configuration: settings) }
        catch { done((error as? LocalizedError)?.errorDescription ?? "Couldn’t plan Send to Several."); return }
        if let problem = ChatAttachmentLimits.problem(sent) { done(problem); return }
        let send = UUID()
        pendingSend = send
        checkTargets(targets) { [weak self] problem in
            guard let self, self.pendingSend == send else { return }
            self.pendingSend = nil
            if let problem { done(problem); return }
            self.fanOut(prompt: text, attachments: sent, targets: targets, headless: headless)
            source.clearComposer(sent: text, attachments: sent)
            done(nil)
        }
    }

    /// Drops the Send to Several waiting for its checks, as closing its picker does.
    func cancelSend() { pendingSend = nil }

    /// The helper first runs the checks each target's start makes, in the same order: the account
    /// folder, once for each provider that has one, then the folder, since each target in a folder
    /// gets its own workspace. An account folder or a folder it would refuse starts nothing, and a
    /// refused account folder's reason starts with its provider and account, as in "Codex account
    /// Personal: …". Replies on the main queue once a check ran.
    func checkTargets(_ targets: [AIConfiguration], reply: @escaping (String?) -> Void) {
        var accounts: [(provider: String, folder: String, name: String)] = []
        for target in targets {
            guard let account = target.account(for: target.provider),
                  !accounts.contains(where: { $0.provider == target.provider && $0.folder == account.directory }) else { continue }
            let title = ACPProvider(rawValue: target.provider)?.title ?? target.provider
            accounts.append((target.provider, account.directory, title + " account " + account.label))
        }
        check(accounts: accounts[...], then: targets.first(where: \.isolate)?.project, reply: reply)
    }

    private func check(accounts: ArraySlice<(provider: String, folder: String, name: String)>, then folder: String?,
                       reply: @escaping (String?) -> Void) {
        guard let account = accounts.first else {
            guard let folder else { reply(nil); return }
            worktreeChecker(folder) { problem in DispatchQueue.main.async { reply(problem) } }
            return
        }
        accountChecker(account.provider, account.folder) { [weak self] problem in
            DispatchQueue.main.async {
                if let problem { reply(account.name + ": " + problem) }
                else { self?.check(accounts: accounts.dropFirst(), then: folder, reply: reply) }
            }
        }
    }

    /// Starts waiting conversations, in order, while the live limit allows. One that already runs, or
    /// has nothing left to send, is not started again.
    private func startWaiting() {
        guard !holding else { return }
        while canStartAnother, !waiting.isEmpty {
            let model = waiting.removeFirst()
            guard !model.active, model.pendingPrompt != nil else { continue }
            if !all.contains(where: { $0 === model }) { all.append(model) }
            start(model)
        }
    }

    /// A conversation stopped running. A Send to Several conversation the helper refused at its
    /// limit before its prompt was sent goes back to its place in the queue, ahead of every target
    /// queued after it, and keeps its prompt. It is tried again after a second, up to `retryLimit`
    /// times, then every `slowRetry` seconds until it starts or Cancel drops it. Any other one that
    /// ended before sending drops its prompt. Then waiting conversations start in the freed slots.
    /// One retry is pending at a time, so a refusal while it waits does not end the hold early.
    private func ended(_ model: ACPModel) {
        if model.fanOutTarget, model.pendingPrompt != nil {
            if model.error == ACPConversationLimit.refusal() {
                model.limitRetries += 1
                model.unread = false
                if model !== current { all.removeAll { $0 === model } }
                let place = waiting.firstIndex(where: { $0.queuePosition > model.queuePosition }) ?? waiting.endIndex
                waiting.insert(model, at: place)
                guard !holding else { return }
                holding = true
                retryLater(model.limitRetries > Self.retryLimit ? Self.slowRetry : 1) { [weak self] in
                    self?.holding = false
                    self?.startWaiting()
                }
                return
            }
            model.dropPendingPrompt()
        }
        startWaiting()
    }

    private static func checkWorktree(_ project: String, reply: @escaping (String?) -> Void) {
        askHelper(reply) { $0.checkWorktree(project: project, reply: $1) }
    }

    private static func checkAccount(_ provider: String, _ folder: String, reply: @escaping (String?) -> Void) {
        askHelper(reply) { $0.checkAccount(provider: provider, profile: folder, reply: $1) }
    }

    /// The conversation Send to Several starts from may have no connection, so each check opens one
    /// of its own.
    private static func askHelper(_ reply: @escaping (String?) -> Void, _ call: (VolantAgentHostProtocol, @escaping (String?) -> Void) -> Void) {
        let connection = NSXPCConnection(serviceName: "com.mysticcoders.volant.AgentHost")
        connection.remoteObjectInterface = NSXPCInterface(with: VolantAgentHostProtocol.self)
        connection.resume()
        let failed = "Agent helper disconnected. Try again."
        guard let proxy = connection.remoteObjectProxyWithErrorHandler({ _ in connection.invalidate(); reply(failed) }) as? VolantAgentHostProtocol else {
            connection.invalidate(); reply(failed); return
        }
        call(proxy) { problem in connection.invalidate(); reply(problem) }
    }

    private func adopt(_ model: ACPModel) {
        model.sessionsElsewhere = { [weak self, weak model] in
            guard let self else { return [] }
            return self.live.filter { $0 !== model }.flatMap { other in [other.state.sessionID, other.resumedSession].compactMap { $0 } }
        }
        model.resumeRefused = { [weak self] session in
            self?.all.forEach { $0.forgetResume(of: session) }
        }
        model.ended = { [weak self, weak model] in
            guard let self, let model else { return }
            self.ended(model)
        }
        model.workspacesElsewhere = { [weak self, weak model] in
            guard let self else { return [] }
            return self.live.filter { $0 !== model }.compactMap(\.workspace)
        }
    }

    /// Views that observe this list redraw on every change inside the current conversation.
    private func followCurrent() {
        currentChanges = current.objectWillChange.sink { [weak self] _ in self?.objectWillChange.send() }
    }

    /// `live` and `shown` change when any conversation starts or ends or is marked unread, and so
    /// does whether the current one may resume, since Resume skips sessions the others hold. Phase
    /// and unread changes of every conversation therefore reach the current conversation's
    /// observers, and through `followCurrent` this list's; transcript updates in the background do not.
    private func watchPhases() {
        let phases = all.map { $0.$state.map(\.phase).removeDuplicates().dropFirst().map { _ in () }.eraseToAnyPublisher() }
        let marks = all.map { $0.$unread.removeDuplicates().dropFirst().map { _ in () }.eraseToAnyPublisher() }
        phaseChanges = Publishers.MergeMany(phases + marks).sink { [weak self] _ in self?.current.objectWillChange.send() }
    }

    /// Only the current conversation polls at the foreground interval, and only it is on screen while
    /// AI Chat is.
    private func updateBackground() {
        for model in all {
            model.background = model !== current
            model.onScreen = chatShown && model === current
        }
    }
}
