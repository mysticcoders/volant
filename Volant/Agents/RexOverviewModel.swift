import AppKit
import SwiftUI
import VolantCore

/// The Rex Overview window's sessions, tabs and panes with their screen previews. UI-owned;
/// callbacks are delivered on the main queue. It reads Rex only while the window is open and the
/// owner has turned on pane previews (`Preferences.rexPanePreviews`, in Settings or in the window),
/// keeping one read outstanding with the helper's watcher like `RexModel`. Preview text lives only
/// in `overview`, in memory, and is cleared when previews are turned off or the window closes.
final class RexOverviewModel: ObservableObject {
    @Published private(set) var overview = RexOverview(sessions: [])
    @Published private(set) var connected = false
    @Published private(set) var loading = false
    @Published private(set) var problem: String?
    @Published var feedback: String?
    @Published private(set) var previewsAllowed: Bool
    /// The pane the keyboard acts on, by session and block ID; re-resolved after every refresh.
    @Published private(set) var selection: RexOverview.Selection?
    /// Sessions the owner minimized, by session ID, most recent last, kept for this Mac. Minimizing
    /// changes only what the window draws; the watcher still reads every pane, so waiting counts
    /// stay right. Entries are never guessed stale, since an unreadable session looks like a closed
    /// one; only the most recent `maximumMinimized` are kept.
    @Published private(set) var minimizedSessions: [String]
    private let defaults: UserDefaults
    static let minimizedKey = "rexOverviewMinimizedSessions"
    static let maximumMinimized = 200
    /// Injected only by isolated tests and fixtures; production reads and focuses through the
    /// signed helper.
    var reader: ((Int, Bool, @escaping (Data?, Int, String?) -> Void) -> Void)?
    var focuser: ((String, String, @escaping (String?) -> Void) -> Void)?
    var activateRex: () -> Void = RexModel.activateRexApp
    /// Writes the owner's choice to the configuration; the app's reload then calls `updateAllowed`.
    private let save: (Bool) throws -> Void
    private var connection: NSXPCConnection?
    private var timer: Timer?
    private var generation = 0
    private var request: UUID?
    private var revision = -1
    private var focusInFlight = false
    private var open = false

    init(previewsAllowed: Bool = false, save: @escaping (Bool) throws -> Void = { _ in }, defaults: UserDefaults = .standard) {
        self.previewsAllowed = previewsAllowed
        self.save = save
        self.defaults = defaults
        minimizedSessions = defaults.stringArray(forKey: Self.minimizedKey) ?? []
        defaults.removeObject(forKey: "rexOverviewMinimizedTabs")
    }

    var minimized: Set<String> { Set(minimizedSessions) }

    func isMinimized(_ session: RexOverview.Session) -> Bool { minimizedSessions.contains(session.sessionID) }

    func toggleMinimized(_ session: RexOverview.Session) {
        var next = minimizedSessions.filter { $0 != session.sessionID }
        if !isMinimized(session) { next.append(session.sessionID) }
        next = Array(next.suffix(Self.maximumMinimized))
        minimizedSessions = next
        defaults.set(next, forKey: Self.minimizedKey)
    }

    /// Minimizes or expands the session holding the selection.
    func toggleSelectedSession() {
        guard let selection, let place = overview.pane(selection) else { return }
        toggleMinimized(place.session)
    }

    /// Whether the grid is showing, so the window's arrow, Tab and Return keys move the selection.
    var keyboardActive: Bool { previewsAllowed && message == nil }

    /// A minimized session is one stop for Left and Right, and Up and Down stay put inside it.
    func move(_ move: RexOverview.Move) {
        let next = overview.move(move, from: selection, minimized: minimized)
        if next != selection { selection = next }
    }

    func select(_ selection: RexOverview.Selection) {
        if overview.pane(selection) != nil { self.selection = selection }
    }

    /// Focuses the selected pane in Rex, as clicking it would.
    func focusSelection() {
        guard let selection, let place = overview.pane(selection) else { return }
        focus(place.pane, in: place.session)
    }

    /// Replaces the overview and keeps the selection on the same pane, or its nearest stand-in.
    private func present(_ next: RexOverview) {
        if next != overview { overview = next }
        let resolved = next.resolve(selection)
        if resolved != selection { selection = resolved }
    }

    var message: String? {
        if let problem { return problem }
        if loading && overview.sessions.isEmpty { return "Loading Rex sessions…" }
        return overview.sessions.isEmpty ? "No Rex sessions are open." : nil
    }

    /// Turns previews on or off from the window. A failed save leaves the choice as it was.
    func allowPreviews(_ allowed: Bool) {
        do { try save(allowed) }
        catch { feedback = "Couldn’t save pane previews: " + error.localizedDescription; return }
        updateAllowed(allowed)
    }

    /// Applies the configured choice, from the window or from Settings.
    func updateAllowed(_ allowed: Bool) {
        guard allowed != previewsAllowed else { return }
        previewsAllowed = allowed
        if allowed { if open { connect() } } else { disconnect() }
    }

    /// The window opened; reading starts once previews are allowed.
    func windowOpened() {
        open = true
        if previewsAllowed { connect() }
    }

    /// The window closed: stop reading and forget everything read.
    func windowClosed() {
        open = false
        disconnect()
    }

    private func connect() {
        guard !connected, previewsAllowed else { return }
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

    private func disconnect() {
        generation += 1
        timer?.invalidate(); timer = nil
        connection?.invalidate(); connection = nil
        request = nil; revision = -1; focusInFlight = false
        connected = false; loading = false; problem = nil
        overview = RexOverview(sessions: [])
        selection = nil
    }

    private func failed(_ message: String, generation current: Int) {
        guard current == generation else { return }
        disconnect()
        problem = message
    }

    /// One read at a time; each reply starts the next. Every read asks for previews, which is why
    /// reading needs the owner's permission.
    func refresh() {
        guard connected, previewsAllowed, request == nil else { return }
        let token = UUID(), current = generation, known = revision
        request = token
        let reply: (Data?, Int, String?) -> Void = { [weak self] data, latest, error in
            let decoded = data.flatMap { try? JSONDecoder().decode(RexOverview.self, from: $0) }
            DispatchQueue.main.async {
                guard let self, self.connected, self.previewsAllowed, current == self.generation, self.request == token else { return }
                self.request = nil
                defer { self.refresh() }
                guard latest != known else { return }
                self.revision = latest
                if let decoded {
                    self.present(decoded)
                    self.problem = nil
                    self.loading = false
                } else {
                    self.present(RexOverview(sessions: []))
                    self.problem = error
                    self.loading = error == nil
                }
            }
        }
        if let reader { reader(known, true, reply) }
        else { proxy(reply: { reply(nil, known + 1, $0) })?.readRexOverview(after: known, preview: true, reply: reply) }
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
    func show(_ overview: RexOverview) {
        present(overview)
        connected = true
        loading = false
    }
}
