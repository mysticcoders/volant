import Foundation

struct ACPMessage: Codable, Identifiable, Equatable {
    var id = UUID().uuidString
    var role: String
    var text: String
}
struct ACPPermission: Codable, Identifiable, Equatable {
    struct Option: Codable, Identifiable, Equatable {
        var optionId: String
        var name: String
        var kind: String
        var id: String { optionId }
    }
    var id: String
    var title: String
    var detail: String
    var options: [Option]
}
struct ACPState: Codable, Equatable {
    var phase = "disconnected"
    var status = "Choose a provider and project to start a conversation."
    var sessionID: String?
    var agentName = ""
    var messages: [ACPMessage] = []
    var permissions: [ACPPermission] = []
    var capabilities = ""
    var busy: Bool { ["starting", "working", "cancelling"].contains(phase) }
}


enum ACPProvider: String, CaseIterable, Identifiable {
    case opencode, cursor, claude, codex
    var id: String { rawValue }
    var title: String {
        switch self {
        case .opencode: return "OpenCode"
        case .cursor: return "Cursor"
        case .claude: return "Claude Code"
        case .codex: return "Codex"
        }
    }
}
