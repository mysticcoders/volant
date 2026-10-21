import AppKit
import SwiftUI
import VolantCore

/// The Rex Overview window's sessions, tabs and panes. UI-owned; callbacks are delivered on the main
/// queue. It keeps one read outstanding with the helper's Rex watcher, like `RexModel`, and asks for
/// pane previews only in Preview mode after the owner turned them on. Preview text lives only in
/// `overview`, in memory, and is cleared when previews or the window are turned off.
final class RexOverviewModel: ObservableObject {
    enum Mode: String { case status, preview }

    @Published private(set) var overview = RexOverview(sessions: [])
    @Published private(set) var connected = false
    @Published private(set) var loading = false
    @Published private(set) var problem: String?
    @Published var feedback: String?
    @Published var mode = Mode.status { didSet { if mode != oldValue { modeChanged() } } }
    /// The owner's choice to let the overview read screen text, kept per Mac. Off until turned on.
    @Published private(set) var previewsAllowed: Bool
    /// Injected only by isolated fixtures; production reads and focuses through the signed helper.
    var reader: ((Int, Bool, @escaping (Data?, Int, String?) -> Void) -> Void)?
    var focuser: ((String, String, @escaping (String?) -> Void) -> Void)?
    var activateRex: () -> Void = RexModel.activateRexApp
    private let defaults: UserDefaults
    static let previewsKey = "rexOverviewPanePreviews"
    private var connection: NSXPCConnection?
    private var timer: Timer?
    private var generation = 0
    private var request: UUID?
    private var revision = -1
    private var focusInFlight = false

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        previewsAllowed = defaults.bool(forKey: Self.previewsKey)
    }

    var readsPreviews: Bool { mode == .preview && previewsAllowed }

    var message: String? {
        if let problem { return problem }
        if loading && overview.sessions.isEmpty { return "Loading Rex sessions…" }
        return overview.sessions.isEmpty ? "No Rex sessions are open." : nil
    }

    func allowPreviews(_ allowed: Bool) {
        defaults.set(allowed, forKey: Self.previewsKey)
        previewsAllowed = allowed
        modeChanged()
    }

    /// Starts reading when the window opens.
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

    /// Stops reading when the window closes, and forgets everything read, previews included.
    func disconnect() {
        generation += 1
        timer?.invalidate(); timer = nil
        connection?.invalidate(); connection = nil
        request = nil; revision = -1; focusInFlight = false
        connected = false; loading = false; problem = nil
        overview = RexOverview(sessions: [])
    }

    private func failed(_ message: String, generation current: Int) {
        guard current == generation else { return }
        disconnect()
        problem = message
    }

    /// A mode change drops what was read, so screen text never outlives Preview mode, and reads
    /// again with the new setting.
    private func modeChanged() {
        guard connected else { return }
        generation += 1
        request = nil; revision = -1
        if !readsPreviews { overview = Self.withoutPreviews(overview) }
        refresh()
    }

    static func withoutPreviews(_ overview: RexOverview) -> RexOverview {
        RexOverview(sessions: overview.sessions.map { session in
            RexOverview.Session(sessionID: session.sessionID, label: session.label, tabs: session.tabs.map { tab in
                RexOverview.Tab(windowID: tab.windowID, label: tab.label, active: tab.active, focusedBlockID: tab.focusedBlockID, panes: tab.panes.map {
                    RexOverview.Pane(blockID: $0.blockID, label: $0.label, title: $0.title, program: $0.program, cwd: $0.cwd, status: $0.status, rect: $0.rect)
                })
            })
        })
    }

    /// One read at a time; each reply starts the next.
    func refresh() {
        guard connected, request == nil else { return }
        let token = UUID(), current = generation, known = revision, preview = readsPreviews
        request = token
        let reply: (Data?, Int, String?) -> Void = { [weak self] data, latest, error in
            let decoded = data.flatMap { try? JSONDecoder().decode(RexOverview.self, from: $0) }
            DispatchQueue.main.async {
                guard let self, self.connected, current == self.generation, self.request == token else { return }
                self.request = nil
                defer { self.refresh() }
                guard latest != known else { return }
                self.revision = latest
                if let decoded {
                    let shown = preview ? decoded : Self.withoutPreviews(decoded)
                    if shown != self.overview { self.overview = shown }
                    self.problem = nil
                    self.loading = false
                } else {
                    self.overview = RexOverview(sessions: [])
                    self.problem = error
                    self.loading = error == nil
                }
            }
        }
        if let reader { reader(known, preview, reply) }
        else { proxy(reply: { reply(nil, known + 1, $0) })?.readRexOverview(after: known, preview: preview, reply: reply) }
    }

    /// Focuses a pane the overview still shows, then brings Rex forward.
    func focus(_ pane: RexOverview.Pane, in session: RexOverview.Session) {
        guard connected, !focusInFlight, overview.sessions.contains(where: { $0.sessionID == session.sessionID && $0.tabs.contains { $0.panes.contains { $0.blockID == pane.blockID } } }) else { return }
        focusInFlight = true
        let current = generation
        let done: (String?) -> Void = { [weak self] error in
            DispatchQueue.main.async {
                guard let self, current == self.generation else { return }
                self.focusInFlight = false
                self.feedback = error
                if error == nil { self.activateRex() }
            }
        }
        if let focuser { focuser(session.sessionID, pane.blockID, done) }
        else { proxy(reply: done)?.focusRexPane(session: session.sessionID, block: pane.blockID, reply: done) }
    }

    private func proxy(reply: @escaping (String) -> Void) -> VolantAgentHostProtocol? {
        connection?.remoteObjectProxyWithErrorHandler { _ in reply("The agent helper is unavailable.") } as? VolantAgentHostProtocol
    }

    /// Replaces the overview directly, for fixtures that render fictional sessions.
    func show(_ overview: RexOverview, connected: Bool = true) {
        self.overview = overview
        self.connected = connected
        loading = false
    }
}
