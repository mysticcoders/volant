import AppKit
import Combine
import VolantCore

final class AppleShortcutsModel: ObservableObject {
    @Published private(set) var entries: [AppleShortcut] = []
    @Published private(set) var loading = false
    @Published private(set) var running = false
    @Published private(set) var message: String?
    @Published private(set) var runMessage: String?
    private var runToken = UUID()
    private var refreshedAt: Date?
    private var connection: NSXPCConnection?
    private var request = UUID()
    var loadOverride: ((@escaping ([AppleShortcut]?, String?) -> Void) -> Void)?
    var runOverride: ((String, @escaping (String?) -> Void) -> Void)?

    deinit { connection?.invalidate() }

    func matches(_ text: String) -> [AppleShortcut] {
        let term = AppleShortcut.queryTerm(text) ?? text
        return entries.filter { term.isEmpty || $0.name.localizedStandardContains(term) }
    }

    private func proxy(failure: @escaping () -> Void) -> VolantAgentHostProtocol? {
        guard ProcessInfo.processInfo.environment["VOLANT_UNIT_TESTING"] != "1" else { return nil }
        if connection == nil {
            let client = NSXPCConnection(serviceName: "com.mysticcoders.volant.AgentHost")
            client.remoteObjectInterface = NSXPCInterface(with: VolantAgentHostProtocol.self)
            client.resume()
            connection = client
        }
        return connection?.remoteObjectProxyWithErrorHandler { [weak self] _ in
            DispatchQueue.main.async {
                self?.connection?.invalidate(); self?.connection = nil
                failure()
            }
        } as? VolantAgentHostProtocol
    }

    func refresh(force: Bool = false) {
        guard !loading, force || refreshedAt == nil || Date().timeIntervalSince(refreshedAt!) > 60 else { return }
        if force && !running { runMessage = nil }
        loading = true
        let token = UUID(); request = token
        let finish: ([AppleShortcut]?, String?) -> Void = { [weak self] values, error in
            DispatchQueue.main.async {
                guard let self, self.request == token, self.loading else { return }
                self.loading = false
                self.refreshedAt = Date()
                self.message = error
                if let values { self.entries = values }
            }
        }
        if let loadOverride { loadOverride(finish); return }
        let failure = { finish(nil, "Couldn’t load Apple Shortcuts. Open Shortcuts, then refresh.") }
        guard let proxy = proxy(failure: failure) else { failure(); return }
        proxy.listAppleShortcuts { data, error in
            guard error == nil, let data, let values = try? JSONDecoder().decode([AppleShortcut].self, from: data) else { failure(); return }
            finish(values, nil)
        }
    }

    func run(_ shortcut: AppleShortcut) {
        guard !running, entries.contains(where: { $0.id == shortcut.id }) else { return }
        let token = UUID(); runToken = token
        running = true; runMessage = "Running shortcut…"
        let finish: (String?) -> Void = { [weak self] error in
            DispatchQueue.main.async {
                guard let self, self.running, self.runToken == token else { return }
                self.running = false
                self.runMessage = error ?? "Shortcut finished."
            }
        }
        if let runOverride { runOverride(shortcut.id, finish); return }
        let failure = { finish("Shortcuts helper disconnected. Check Shortcuts before retrying.") }
        guard let proxy = proxy(failure: failure) else { failure(); return }
        proxy.runAppleShortcut(id: shortcut.id, reply: finish)
    }

    func openApp() {
        guard NSWorkspace.shared.open(URL(string: "shortcuts://")!) else { message = "Couldn’t open the Shortcuts app."; return }
    }
}
