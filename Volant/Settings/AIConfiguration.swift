import Foundation

struct AIConfiguration: Codable, Equatable {
    var provider = "opencode"
    var project = ""
    enum CodingKeys: String, CodingKey { case provider, project }
    init() {}
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        provider = try c.decodeIfPresent(String.self, forKey: .provider) ?? "opencode"
        project = try c.decodeIfPresent(String.self, forKey: .project) ?? ""
        guard ACPProvider(rawValue: provider) != nil else { throw CocoaError(.fileReadCorruptFile) }
    }
    static func load(at url: URL = Preferences.configURL) throws -> Self {
        guard let object = try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any] else { throw CocoaError(.fileReadCorruptFile) }
        guard let value = object["ai"] else { return Self() }
        return try JSONDecoder().decode(Self.self, from: JSONSerialization.data(withJSONObject: value))
    }
    func save(at url: URL = Preferences.configURL, expected: AIConfiguration? = nil) throws {
        if let expected, try Self.load(at: url) != expected { throw CocoaError(.fileWriteFileExists) }
        guard ACPProvider(rawValue: provider) != nil else { throw CocoaError(.fileWriteInvalidFileName) }
        // Patch the latest file; preserve unknown settings inside and outside AI.
        guard var object = try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any] else { throw CocoaError(.fileReadCorruptFile) }
        var ai = object["ai"] as? [String: Any] ?? [:]
        guard let values = try JSONSerialization.jsonObject(with: JSONEncoder().encode(self)) as? [String: Any] else { throw CocoaError(.fileWriteUnknown) }
        for (key, value) in values { ai[key] = value }
        object["ai"] = ai
        try JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys]).write(to: url, options: .atomic)
    }
}
