import Foundation
import VolantCore

/// Asks the agent helper which ACP agents are installed. Only the helper can see the owner's
/// install locations; the sandboxed app cannot. Detection starts nothing and reads no credentials.
final class ACPAgentDetection: ObservableObject {
    @Published private(set) var agents: [ACPAgentAvailability] = []
    @Published private(set) var checking = false
    @Published private(set) var message: String?
    // Injected only by isolated fixtures; production reads through the signed helper.
    var reader: ((@escaping (Data?, String?) -> Void) -> Void)?
    private var connection: NSXPCConnection?
    private var request = UUID()

    func detect() {
        let current = UUID()
        request = current; checking = true; message = nil
        let reply: (Data?, String?) -> Void = { [weak self] data, error in
            DispatchQueue.main.async {
                guard let self, self.request == current else { return }
                self.checking = false
                self.connection?.invalidate(); self.connection = nil
                if let data, error == nil, let found = try? JSONDecoder().decode([ACPAgentAvailability].self, from: data) {
                    let order: [ACPAgentAvailability.State] = [.ready, .needsAdapter, .needsNode, .notInstalled]
                    self.agents = found.sorted {
                        let left = order.firstIndex(of: $0.state) ?? 0, right = order.firstIndex(of: $1.state) ?? 0
                        return left == right ? ($0.title < $1.title) : left < right
                    }
                } else {
                    self.message = error ?? "Couldn’t check for installed agents."
                }
            }
        }
        if let reader { reader(reply); return }
        connection?.invalidate()
        let connection = NSXPCConnection(serviceName: "com.mysticcoders.volant.AgentHost")
        connection.remoteObjectInterface = NSXPCInterface(with: VolantAgentHostProtocol.self)
        self.connection = connection
        connection.resume()
        let proxy = connection.remoteObjectProxyWithErrorHandler { _ in reply(nil, "The agent helper is unavailable.") } as? VolantAgentHostProtocol
        proxy?.detectACPAgents(reply: reply)
    }

    func cancel() {
        request = UUID(); checking = false
        connection?.invalidate(); connection = nil
    }
}

extension ACPAgentAvailability {
    var title: String { ACPProvider(rawValue: provider)?.title ?? provider }
    var symbol: String {
        switch state {
        case .ready: return "checkmark.circle.fill"
        case .needsAdapter, .needsNode: return "exclamationmark.circle.fill"
        case .notInstalled: return "circle.dashed"
        }
    }
}
