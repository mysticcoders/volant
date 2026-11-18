import Foundation

/// The MCP server settings in config.json under `mcpServer`: off by default, per Mac, never in
/// `SettingsSync.keys`. Each write capability has its own switch, and the owner can disconnect an app
/// by the client name its bridge configuration gives.
public struct MCPPreferences: Codable, Equatable, Sendable {
    public var enabled: Bool
    /// Lets AI apps create notes and append to them.
    public var writesNotes: Bool
    /// Lets AI apps add snippets.
    public var writesSnippets: Bool
    /// Lets AI apps add quicklinks.
    public var writesQuicklinks: Bool
    /// Client names that have connected, in the order they first did, for Settings.
    public var knownClients: [String]
    /// Client names the owner disconnected; their requests are refused until allowed again.
    public var disconnectedClients: [String]

    public init(enabled: Bool = false, writesNotes: Bool = false, writesSnippets: Bool = false, writesQuicklinks: Bool = false,
                knownClients: [String] = [], disconnectedClients: [String] = []) {
        self.enabled = enabled
        self.writesNotes = writesNotes
        self.writesSnippets = writesSnippets
        self.writesQuicklinks = writesQuicklinks
        self.knownClients = knownClients
        self.disconnectedClients = disconnectedClients
    }

    /// Missing or mistyped values fall back to defaults, and client lists keep only valid names, so a
    /// hand-edited or newer config still loads.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        func flag(_ key: CodingKeys) -> Bool { (try? c.decodeIfPresent(Bool.self, forKey: key)) ?? false }
        func names(_ key: CodingKeys) -> [String] {
            var seen = Set<String>()
            return ((try? c.decodeIfPresent([String].self, forKey: key)) ?? []).compactMap(MCPEndpoint.clientName).filter { seen.insert($0).inserted }
        }
        self.init(enabled: flag(.enabled), writesNotes: flag(.writesNotes), writesSnippets: flag(.writesSnippets),
                  writesQuicklinks: flag(.writesQuicklinks), knownClients: names(.knownClients), disconnectedClients: names(.disconnectedClients))
    }

    /// Whether a client may use the server: it is on and the owner hasn't disconnected that app.
    public func refusal(for client: String) -> MCPRefusal? {
        if !enabled { return .serverOff }
        if disconnectedClients.contains(client) { return .disconnected }
        return nil
    }
}
