import Foundation

/// Passive, bounded terminal excerpt. Never interpreted as a command or stored on disk.
struct HerdrAttention: Equatable {
    let text: String
    let truncated: Bool

    static func preview(_ data: Data) throws -> Self {
        guard data.count <= 128_000, let raw = String(data: data, encoding: .utf8) else {
            throw CocoaError(.fileReadCorruptFile)
        }
        // Detection reads are plain text. Strip stray control/bidi characters defensively.
        let clean = String(String.UnicodeScalarView(raw.unicodeScalars.filter {
            $0 == "\n" || $0 == "\t" || (!CharacterSet.controlCharacters.contains($0) &&
                !CharacterSet(charactersIn: "\u{202A}\u{202B}\u{202C}\u{202D}\u{202E}\u{2066}\u{2067}\u{2068}\u{2069}").contains($0))
        })).trimmingCharacters(in: .whitespacesAndNewlines)
        let lines = clean.components(separatedBy: "\n")
        let tail = lines.suffix(30).joined(separator: "\n")
        let truncated = lines.count > 30 || tail.count > 4_000
        return Self(text: String(tail.suffix(4_000)), truncated: truncated)
    }

    static func matches(_ target: AgentSession, in sessions: [AgentSession]) -> Bool {
        sessions.contains { $0.id == target.id &&
            $0.sessionIdentity == target.sessionIdentity && $0.agentStatus == "blocked" }
    }
}
