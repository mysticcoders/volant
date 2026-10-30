import Foundation

@objc public protocol VolantAIHostProtocol {
    func start(configuration: Data, key: String, reply: @escaping (String?) -> Void)
    func read(reply: @escaping (Data?, String?) -> Void)
    func prompt(text: String, reply: @escaping (String?) -> Void)
    /// A prompt with owner-chosen attachments, a JSON array of `ChatAttachment`.
    func promptWithContext(text: String, attachments: Data, reply: @escaping (String?) -> Void)
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
        case .local: return String(localized: "Local Models", table: "Core", comment: "AI connection kind in AI Settings")
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
    public var title: String { switch self { case .openAI: return "OpenAI"; case .anthropic: return "Anthropic"; case .compatible: return String(localized: "OpenAI-compatible", table: "Core", comment: "AI API provider for servers that speak the OpenAI API") } }
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
    public var errorDescription: String? { hostMessage.text }

    /// The code `VolantAIHost` sends for this error, which the app shows in the owner's language.
    public var hostMessage: HostMessage {
        switch self {
        case .configuration: return HostMessage(.aiConfiguration)
        case .key: return HostMessage(.aiKey)
        case .response: return HostMessage(.aiResponse)
        case .limit: return HostMessage(.aiLimit)
        case .incomplete: return HostMessage(.aiIncomplete)
        case .unsupported: return HostMessage(.aiUnsupported)
        case .http(let code):
            switch code {
            case 401, 403: return HostMessage(.aiRejected)
            case 429: return HostMessage(.aiRateLimited)
            default: return HostMessage(.aiHTTPStatus, String(code))
            }
        }
    }

    /// The message for any error from an AI connection, worded in this process.
    public static func message(_ error: Error) -> String { hostMessage(error).text }

    /// The code for any error from an AI connection, which is what the AI helper replies with.
    public static func wire(_ error: Error) -> String { hostMessage(error).wire }

    /// The message for a connection error, or "couldn't reach the server" for one that isn't.
    private static func hostMessage(_ error: Error) -> HostMessage {
        (error as? AIHTTPError)?.hostMessage ?? HostMessage(.aiUnreachable)
    }
}
public struct AILocalServer: Identifiable, Equatable {
    public var name: String
    public var endpoint: String
    public var models: [String] = []
    public var message: String = String(localized: "Checking…", table: "Core", comment: "Local AI server status while Volant checks whether it is running")
    public var id: String { endpoint }
    public var configuration: AIHTTPConfiguration { AIHTTPConfiguration(provider: .compatible, endpoint: endpoint, local: true) }
    public static let candidates = [
        AILocalServer(name: "Ollama · 11434", endpoint: "http://127.0.0.1:11434/v1"),
        AILocalServer(name: "LM Studio · 1234", endpoint: "http://127.0.0.1:1234/v1"),
        AILocalServer(name: "Local API · 8000", endpoint: "http://127.0.0.1:8000/v1")
    ]

    public init(name: String, endpoint: String, models: [String] = [], message: String = String(localized: "Checking…", table: "Core", comment: "Local AI server status while Volant checks whether it is running")) {
        self.name = name
        self.endpoint = endpoint
        self.models = models
        self.message = message
    }
}
