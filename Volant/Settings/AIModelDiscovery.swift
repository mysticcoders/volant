import Foundation
import Combine

/// Created by AI Settings only; no startup, launcher typing or background probing.
final class AIModelDiscovery: ObservableObject {
    @Published var servers: [AILocalServer] = []
    @Published var models: [String] = []
    @Published var message: String?
    @Published var loading = false
    private var generation = UUID()
    private var connections: [NSXPCConnection] = []
    var lookupOverride: ((AIHTTPConfiguration, String, @escaping ([String]?, String?) -> Void) -> Void)?
    func cancel() {
        generation = UUID(); loading = false
        connections.forEach { $0.invalidate() }; connections = []
    }
    func discover() {
        cancel(); servers = AILocalServer.candidates; let current = generation
        for candidate in servers {
            lookup(candidate.configuration, key: "") { [weak self] models, error in
                guard let self, self.generation == current, let index = self.servers.firstIndex(where: { $0.id == candidate.id }) else { return }
                self.servers[index].models = models ?? []
                self.servers[index].message = models.map { $0.isEmpty ? "Server available · no models listed" : "\($0.count) models available" } ?? (error ?? "Unavailable")
            }
        }
    }
    func refresh(_ config: AIHTTPConfiguration, key: String) {
        cancel(); models = []; message = nil; loading = true; let current = generation
        lookup(config, key: key) { [weak self] models, error in
            guard let self, self.generation == current else { return }
            self.loading = false; self.models = models ?? []
            self.message = error ?? (models?.isEmpty == false ? "Connection verified. Choose a model." : "Connected; no models listed. Enter a model ID manually.")
        }
    }
    private func lookup(_ config: AIHTTPConfiguration, key: String, completion: @escaping ([String]?, String?) -> Void) {
        if let lookupOverride { lookupOverride(config, key, completion); return }
        do {
            try config.validate(requireModel: false)
            let connection = NSXPCConnection(serviceName: "com.mysticcoders.volant.AIHost")
            connections.append(connection)
            connection.remoteObjectInterface = NSXPCInterface(with: VolantAIHostProtocol.self)
            connection.resume()
            var completed = false
            let finish: ([String]?, String?) -> Void = { [weak self] models, error in DispatchQueue.main.async {
                guard !completed else { return }; completed = true
                self?.connections.removeAll { $0 === connection }; connection.invalidate(); completion(models, error)
            } }
            DispatchQueue.main.asyncAfter(deadline: .now() + (config.local ? 4 : 20)) { finish(nil, "No response. Check that the server is running.") }
            let proxy = connection.remoteObjectProxyWithErrorHandler { _ in finish(nil, "Couldn’t reach the model service.") } as? VolantAIHostProtocol
            proxy?.models(configuration: try JSONEncoder().encode(config), key: key) { data, error in
                finish(data.flatMap { try? JSONDecoder().decode([String].self, from: $0) }, error)
            }
        } catch { completion(nil, AIHTTPError.message(error)) }
    }
    deinit { connections.forEach { $0.invalidate() } }
}
