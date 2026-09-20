import Foundation
import VolantCore

actor AIHTTPConversation {
    private var state = ACPState()
    private var history: [ACPMessage] = []
    private var config: AIHTTPConfiguration?
    private var key = ""
    private var turn: Task<Void, Never>?
    private var generation = UUID()
    private let transport: AIHTTPTransport
    init(transport: AIHTTPTransport = AIHTTPTransport()) { self.transport = transport }
    func start(_ config: AIHTTPConfiguration, key: String) throws {
        try config.validate()
        if !config.local && key.isEmpty { throw AIHTTPError.key }
        cancel(); self.config = config; self.key = key; history = []
        state = ACPState(); state.phase = "ready"; state.status = "Ready"; state.agentName = config.model
    }
    func snapshot() throws -> Data { try JSONEncoder().encode(state) }
    func prompt(_ text: String) throws {
        guard let config, turn == nil, state.phase == "ready", !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw AIHTTPError.configuration }
        guard text.utf8.count <= 65_536, history.count < 98, state.messages.count < 100,
              state.messages.reduce(0, { $0 + $1.text.utf8.count }) + text.utf8.count <= 262_144 else { throw AIHTTPError.limit }
        let user = ACPMessage(role: "You", text: text), reply = ACPMessage(role: "Agent", text: "")
        state.messages += [user, reply]; state.phase = "working"; state.status = "Responding…"
        generation = UUID(); let token = generation, key = key, input = history + [user]
        turn = Task {
            do {
                try await transport.stream(config, key: key, messages: input) { chunk in try self.append(chunk, token: token) }
                guard generation == token else { return }
                guard let answer = state.messages.last, !answer.text.isEmpty else { throw AIHTTPError.response }
                history = input + [answer]
                state.phase = "ready"; state.status = "Ready"; turn = nil
            } catch {
                guard generation == token else { return }
                state.phase = "ready"; state.status = AIHTTPError.message(error); turn = nil
            }
        }
    }
    private func append(_ text: String, token: UUID) throws {
        guard generation == token, let last = state.messages.indices.last else { throw CancellationError() }
        guard state.messages.reduce(0, { $0 + $1.text.utf8.count }) + text.utf8.count <= 262_144 else { throw AIHTTPError.limit }
        state.messages[last].text += text
    }
    func cancel() {
        generation = UUID(); turn?.cancel(); turn = nil
        state.phase = config == nil ? "disconnected" : "ready"; state.status = "Stopped"
    }
    func stop() { cancel(); key = ""; config = nil; history = []; state = ACPState() }
}
final class AIHTTPHost: NSObject, VolantAIHostProtocol {
    let conversation = AIHTTPConversation()
    private let transport = AIHTTPTransport()
    func stop() { transport.session.invalidateAndCancel(); Task { await conversation.stop() } }
    func start(configuration: Data, key: String, reply: @escaping (String?) -> Void) {
        Task { do { guard configuration.count <= 8192 else { throw AIHTTPError.configuration }
            try await conversation.start(JSONDecoder().decode(AIHTTPConfiguration.self, from: configuration), key: key); reply(nil)
        } catch { reply(AIHTTPError.message(error)) } }
    }
    func read(reply: @escaping (Data?, String?) -> Void) { Task { do { reply(try await conversation.snapshot(), nil) } catch { reply(nil, "Couldn’t read conversation.") } } }
    func prompt(text: String, reply: @escaping (String?) -> Void) { Task { do { try await conversation.prompt(text); reply(nil) } catch { reply(AIHTTPError.message(error)) } } }
    func cancel(reply: @escaping () -> Void) { Task { await conversation.cancel(); reply() } }
    func models(configuration: Data, key: String, reply: @escaping (Data?, String?) -> Void) {
        Task { do { guard configuration.count <= 8192 else { throw AIHTTPError.configuration }
            let config = try JSONDecoder().decode(AIHTTPConfiguration.self, from: configuration)
            reply(try JSONEncoder().encode(await transport.models(config, key: key)), nil)
        } catch { reply(nil, AIHTTPError.message(error)) } }
    }
}
