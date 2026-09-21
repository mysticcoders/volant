import Foundation

@objc public protocol VolantAIHostProtocol {
    func start(configuration: Data, key: String, reply: @escaping (String?) -> Void)
    func read(reply: @escaping (Data?, String?) -> Void)
    func prompt(text: String, reply: @escaping (String?) -> Void)
    func cancel(reply: @escaping () -> Void)
    func models(configuration: Data, key: String, reply: @escaping (Data?, String?) -> Void)
}

public enum AIConnectionKind: String, Codable, CaseIterable, Identifiable {
    case acp, byok, local, apple
    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .acp: return "ACP"
        case .byok: return "BYOK"
        case .local: return "Local Models"
        case .apple: return "Apple Intelligence"
        }
    }
    /// Apple's model runs on this Mac through the system, so it needs no endpoint, key or helper.
    /// The other kinds all describe a service to reach.
    public var usesHTTP: Bool { self == .byok || self == .local }
}
public enum AIAPIProvider: String, Codable, CaseIterable, Identifiable {
    case openAI, anthropic, compatible
    public var id: String { rawValue }
    public var title: String { switch self { case .openAI: return "OpenAI"; case .anthropic: return "Anthropic"; case .compatible: return "OpenAI-compatible" } }
    public var endpoint: String { switch self { case .openAI: return "https://api.openai.com/v1"; case .anthropic: return "https://api.anthropic.com/v1"; case .compatible: return "" } }
}
public struct AIHTTPConfiguration: Codable, Equatable {
    public var provider: AIAPIProvider = .openAI
    public var endpoint = "https://api.openai.com/v1"
    public var model = ""
    public var local = false
    public var credentialID: String { "\(provider.rawValue):\(endpoint.trimmingCharacters(in: CharacterSet(charactersIn: "/")))" }
    public func baseURL() throws -> URL {
        guard let parts = URLComponents(string: endpoint), let url = parts.url, let host = parts.host,
              parts.user == nil, parts.password == nil, parts.query == nil, parts.fragment == nil,
              !endpoint.contains(where: { $0.isWhitespace }), endpoint.utf8.count <= 2048 else { throw AIHTTPError.configuration }
        let loopback = ["localhost", "127.0.0.1", "::1", "[::1]"].contains(host.lowercased())
        guard parts.scheme == "https" || (parts.scheme == "http" && loopback), !local || loopback else { throw AIHTTPError.configuration }
        if provider != .compatible && endpoint != provider.endpoint { throw AIHTTPError.configuration }
        guard !local || provider == .compatible else { throw AIHTTPError.configuration }
        return url
    }
    public func validate(requireModel: Bool = true) throws {
        _ = try baseURL()
        guard model.utf8.count <= 256, !model.contains(where: { $0.isNewline || $0 == "\0" }),
              !requireModel || !model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw AIHTTPError.configuration }
    }

    public init(provider: AIAPIProvider = .openAI, endpoint: String = "https://api.openai.com/v1", model: String = "", local: Bool = false) {
        self.provider = provider
        self.endpoint = endpoint
        self.model = model
        self.local = local
    }
}
public enum AIHTTPError: Error, LocalizedError {
    case configuration, key, response, limit, incomplete, unsupported, http(Int)
    public var errorDescription: String? {
        switch self {
        case .configuration: return "Choose a model and a valid HTTPS API URL, or a loopback URL for local models."
        case .key: return "Add an API key in AI Settings before connecting."
        case .response: return "The server returned an unsupported response. Check the provider and endpoint."
        case .limit: return "This conversation reached its size limit. Start a new conversation."
        case .incomplete: return "The response stopped before completion. You can try again."
        case .unsupported: return "This connection supports text chat only; the server requested an unsupported operation."
        case .http(let code):
            switch code {
            case 401, 403: return "The server rejected access. Check your API key and model permissions."
            case 429: return "The server's rate or usage limit was reached. Try again later."
            default: return "The AI server returned HTTP \(code). Check your connection settings."
            }
        }
    }
    public static func message(_ error: Error) -> String {
        (error as? AIHTTPError)?.errorDescription ?? "Couldn’t reach the AI server. Check its address and whether it is running."
    }
}
public struct AILocalServer: Identifiable, Equatable {
    public var name: String
    public var endpoint: String
    public var models: [String] = []
    public var message: String = "Checking…"
    public var id: String { endpoint }
    public var configuration: AIHTTPConfiguration { AIHTTPConfiguration(provider: .compatible, endpoint: endpoint, local: true) }
    public static let candidates = [
        AILocalServer(name: "Ollama · 11434", endpoint: "http://127.0.0.1:11434/v1"),
        AILocalServer(name: "LM Studio · 1234", endpoint: "http://127.0.0.1:1234/v1"),
        AILocalServer(name: "Local API · 8000", endpoint: "http://127.0.0.1:8000/v1")
    ]

    public init(name: String, endpoint: String, models: [String] = [], message: String = "Checking…") {
        self.name = name
        self.endpoint = endpoint
        self.models = models
        self.message = message
    }
}
