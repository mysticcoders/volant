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
    /// Lets AI apps start, pause, resume and end Focus sessions.
    public var controlsFocus: Bool
    /// Lets AI apps take, end, skip and pause breaks.
    public var controlsBreaks: Bool
    /// Sensitive tools: each also asks in Volant on every call unless the owner chose Always Allow.
    public var sharesClipboard: Bool
    public var searchesFiles: Bool
    public var convertsCurrency: Bool
    public var checksWeather: Bool
    /// `client/tool` pairs the owner chose Always Allow for; cleared for a client when it's disconnected.
    public var alwaysAllowed: [String]
    /// Client names that have connected, in the order they first did, for Settings.
    public var knownClients: [String]
    /// Client names the owner disconnected; their requests are refused until allowed again.
    public var disconnectedClients: [String]

    public init(enabled: Bool = false, writesNotes: Bool = false, writesSnippets: Bool = false, writesQuicklinks: Bool = false,
                controlsFocus: Bool = false, controlsBreaks: Bool = false, sharesClipboard: Bool = false, searchesFiles: Bool = false,
                convertsCurrency: Bool = false, checksWeather: Bool = false, alwaysAllowed: [String] = [],
                knownClients: [String] = [], disconnectedClients: [String] = []) {
        self.enabled = enabled
        self.writesNotes = writesNotes
        self.writesSnippets = writesSnippets
        self.writesQuicklinks = writesQuicklinks
        self.controlsFocus = controlsFocus
        self.controlsBreaks = controlsBreaks
        self.sharesClipboard = sharesClipboard
        self.searchesFiles = searchesFiles
        self.convertsCurrency = convertsCurrency
        self.checksWeather = checksWeather
        self.alwaysAllowed = alwaysAllowed
        self.knownClients = knownClients
        self.disconnectedClients = disconnectedClients
    }

    /// Missing or mistyped values fall back to defaults, and client lists keep only valid names, so a
    /// hand-edited or newer config still loads.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        func flag(_ key: CodingKeys) -> Bool { (try? c.decodeIfPresent(Bool.self, forKey: key)) ?? false }
        func grants() -> [String] {
            var seen = Set<String>()
            return ((try? c.decodeIfPresent([String].self, forKey: .alwaysAllowed)) ?? []).filter { grant in
                let parts = grant.split(separator: "/", omittingEmptySubsequences: false)
                return parts.count == 2 && MCPEndpoint.clientName(String(parts[0])) == String(parts[0]) && !parts[1].isEmpty && seen.insert(grant).inserted
            }
        }
        func names(_ key: CodingKeys) -> [String] {
            var seen = Set<String>()
            return ((try? c.decodeIfPresent([String].self, forKey: key)) ?? []).compactMap(MCPEndpoint.clientName).filter { seen.insert($0).inserted }
        }
        self.init(enabled: flag(.enabled), writesNotes: flag(.writesNotes), writesSnippets: flag(.writesSnippets),
                  writesQuicklinks: flag(.writesQuicklinks), controlsFocus: flag(.controlsFocus), controlsBreaks: flag(.controlsBreaks),
                  sharesClipboard: flag(.sharesClipboard), searchesFiles: flag(.searchesFiles), convertsCurrency: flag(.convertsCurrency),
                  checksWeather: flag(.checksWeather), alwaysAllowed: grants(), knownClients: names(.knownClients), disconnectedClients: names(.disconnectedClients))
    }

    /// The grant key for one client and tool.
    public static func grant(client: String, tool: String) -> String { client + "/" + tool }

    /// Whether the owner chose Always Allow for this client and tool.
    public func alwaysAllows(client: String, tool: String) -> Bool { alwaysAllowed.contains(Self.grant(client: client, tool: tool)) }

    /// Disconnects a client and forgets every Always Allow it had.
    public mutating func disconnect(_ client: String) {
        if !disconnectedClients.contains(client) { disconnectedClients.append(client) }
        alwaysAllowed.removeAll { $0.hasPrefix(client + "/") }
    }

    /// Forgets a client's Always Allow choices, so each sensitive call asks again.
    public mutating func askAgain(_ client: String) {
        alwaysAllowed.removeAll { $0.hasPrefix(client + "/") }
    }

    /// Whether a client may use the server: it is on and the owner hasn't disconnected that app.
    public func refusal(for client: String) -> MCPRefusal? {
        if !enabled { return .serverOff }
        if disconnectedClients.contains(client) { return .disconnected }
        return nil
    }
}
