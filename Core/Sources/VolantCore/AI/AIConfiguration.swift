import Foundation

public struct AIConfiguration: Codable, Equatable {
    public var provider = ""
    public var connection: AIConnectionKind = .acp
    public var api = AIHTTPConfiguration()
    public var localAPI = AIHTTPConfiguration(provider: .compatible, endpoint: "http://127.0.0.1:11434/v1", local: true)
    public var http: AIHTTPConfiguration { connection == .local ? localAPI : api }
    public var isConfigured: Bool { connection == .acp ? ACPProvider(rawValue: provider) != nil : (try? http.validate()) != nil }
    public var project = ""
    public enum CodingKeys: String, CodingKey { case provider, project, connection, api, localAPI }
    public init() {}
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        provider = try c.decodeIfPresent(String.self, forKey: .provider) ?? ""
        project = try c.decodeIfPresent(String.self, forKey: .project) ?? ""
        connection = try c.decodeIfPresent(AIConnectionKind.self, forKey: .connection) ?? .acp
        api = try c.decodeIfPresent(AIHTTPConfiguration.self, forKey: .api) ?? AIHTTPConfiguration()
        localAPI = try c.decodeIfPresent(AIHTTPConfiguration.self, forKey: .localAPI) ?? AIHTTPConfiguration(provider: .compatible, endpoint: "http://127.0.0.1:11434/v1", local: true)
        guard !api.local, localAPI.local else { throw CocoaError(.fileReadCorruptFile) }

        guard provider.isEmpty || ACPProvider(rawValue: provider) != nil else { throw CocoaError(.fileReadCorruptFile) }
    }
    public static func load(at url: URL = Preferences.configURL) throws -> Self {
        guard let object = try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any] else { throw CocoaError(.fileReadCorruptFile) }
        guard let value = object["ai"] else { return Self() }
        return try JSONDecoder().decode(Self.self, from: JSONSerialization.data(withJSONObject: value))
    }
    public func save(at url: URL = Preferences.configURL, expected: AIConfiguration? = nil) throws {
        if let expected, try Self.load(at: url) != expected { throw CocoaError(.fileWriteFileExists) }
        guard provider.isEmpty || ACPProvider(rawValue: provider) != nil else { throw CocoaError(.fileWriteInvalidFileName) }
        // Patch the latest file; preserve unknown settings inside and outside AI.
        guard var object = try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any] else { throw CocoaError(.fileReadCorruptFile) }
        var ai = object["ai"] as? [String: Any] ?? [:]
        guard let values = try JSONSerialization.jsonObject(with: JSONEncoder().encode(self)) as? [String: Any] else { throw CocoaError(.fileWriteUnknown) }
        for (key, value) in values {
            if let fields = value as? [String: Any], var previous = ai[key] as? [String: Any] {
                fields.forEach { previous[$0.key] = $0.value }; ai[key] = previous
            } else { ai[key] = value }
        }
        object["ai"] = ai
        try JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys]).write(to: url, options: .atomic)
    }
}
