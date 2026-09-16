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
    var status = "Connect to your AI provider to start chatting."
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

/// ACP requires an absolute cwd; general chat does not require a user-selected project.
enum ACPWorkingDirectory {
    static func resolve(project: String, generalChat: URL) throws -> String {
        let url: URL
        if project.isEmpty {
            try FileManager.default.createDirectory(at: generalChat, withIntermediateDirectories: true)
            url = generalChat
        } else {
            guard project.hasPrefix("/"), !project.contains("\0") else { throw CocoaError(.fileReadInvalidFileName) }
            url = URL(fileURLWithPath: project)
        }
        var directory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &directory), directory.boolValue else { throw CocoaError(.fileReadNoSuchFile) }
        return url.resolvingSymlinksInPath().path
    }
}
