import Foundation

/// What `volant-mcp` must replay when it reconnects to a Volant that quit or restarted. A modern
/// client's requests carry everything in `_meta`, so they need nothing; a legacy client sent
/// `initialize` once, so the bridge keeps that request and resends it, under its own id, to the new
/// connection, followed by `notifications/initialized`, and drops the reply so the client never sees
/// a second answer.
public struct MCPBridgeReplay: Equatable, Sendable {
    /// The id the bridge gives a replayed `initialize`; replies with it are the bridge's own.
    public static let replayID = "volant-bridge-replay"

    private var initializeParams: MCPValue?
    private var initialized = false

    public init() {}

    /// Notes a line the client sent, keeping its `initialize` request and whether it finished the handshake.
    public mutating func observe(_ line: Data) {
        guard let message = try? JSONDecoder().decode(MCPValue.self, from: line), let method = message["method"]?.string else { return }
        if method == "initialize" {
            initializeParams = message["params"] ?? .object([:])
            initialized = false
        } else if method == "notifications/initialized" {
            initialized = true
        }
    }

    /// The lines to send a new connection before anything else, after the bridge's handshake.
    public func lines() -> [Data] {
        guard let initializeParams else { return [] }
        var lines = [MCPValue.object(["jsonrpc": .string("2.0"), "id": .string(Self.replayID), "method": .string("initialize"),
                                      "params": initializeParams]).line()]
        if initialized {
            lines.append(MCPValue.object(["jsonrpc": .string("2.0"), "method": .string("notifications/initialized")]).line())
        }
        return lines
    }

    /// Whether a line from Volant answers a replayed `initialize`, and so must not reach the client.
    public static func isReplayReply(_ line: Data) -> Bool {
        (try? JSONDecoder().decode(MCPValue.self, from: line))?["id"] == .string(replayID)
    }
}
