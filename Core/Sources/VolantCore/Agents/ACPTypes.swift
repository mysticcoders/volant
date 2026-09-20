import Foundation

public struct ACPMessage: Codable, Identifiable, Equatable {
    public var id = UUID().uuidString
    public var role: String
    public var text: String

    public init(id: String = UUID().uuidString, role: String, text: String) {
        self.id = id
        self.role = role
        self.text = text
    }
}
public struct ACPPermission: Codable, Identifiable, Equatable {
    public struct Option: Codable, Identifiable, Equatable {
        public var optionId: String
        public var name: String
        public var kind: String
        public var id: String { optionId }

        public init(optionId: String, name: String, kind: String) {
            self.optionId = optionId
            self.name = name
            self.kind = kind
        }
    }
    public var id: String
    public var title: String
    public var detail: String
    public var options: [Option]

    public init(id: String, title: String, detail: String, options: [Option]) {
        self.id = id
        self.title = title
        self.detail = detail
        self.options = options
    }
}
public struct ACPState: Codable, Equatable {
    public var phase = "disconnected"
    public var status = "Connect to your AI provider to start chatting."
    public var sessionID: String?
    public var agentName = ""
    public var messages: [ACPMessage] = []
    public var permissions: [ACPPermission] = []
    public var capabilities = ""
    public var busy: Bool { ["starting", "working", "cancelling"].contains(phase) }

    public init(phase: String = "disconnected", status: String = "Connect to your AI provider to start chatting.", sessionID: String? = nil, agentName: String = "", messages: [ACPMessage] = [], permissions: [ACPPermission] = [], capabilities: String = "") {
        self.phase = phase
        self.status = status
        self.sessionID = sessionID
        self.agentName = agentName
        self.messages = messages
        self.permissions = permissions
        self.capabilities = capabilities
    }
}


public enum ACPProvider: String, CaseIterable, Identifiable {
    case opencode, cursor, claude, codex
    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .opencode: return "OpenCode"
        case .cursor: return "Cursor"
        case .claude: return "Claude Code"
        case .codex: return "Codex"
        }
    }
}

/// ACP requires an absolute cwd; general chat does not require a user-selected project.
public enum ACPWorkingDirectory {
    public static func resolve(project: String, generalChat: URL) throws -> String {
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
