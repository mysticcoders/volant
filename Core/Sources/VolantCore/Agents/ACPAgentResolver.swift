import Foundation

/// How to start one provider's ACP agent: the executable, its arguments and extra environment.
public struct ACPLaunch: Equatable {
    public let executable: String
    public let arguments: [String]
    public let environment: [String: String]
}

/// What detection found for one provider, shown in Settings before anything is started.
public struct ACPAgentAvailability: Codable, Equatable, Identifiable {
    public enum State: String, Codable {
        case ready, needsAdapter, needsNode, notInstalled
    }
    public let provider: String
    public let state: State
    public let detail: String
    public let path: String?
    public var id: String { provider }

    public init(provider: String, state: State, detail: String, path: String?) {
        self.provider = provider
        self.state = state
        self.detail = detail
        self.path = path
    }
}

public struct ACPResolutionError: LocalizedError, Equatable {
    public let state: ACPAgentAvailability.State
    public let message: String
    public var errorDescription: String? { message }
}

/// Finds agent executables in the places people install them. Connecting and detection share this
/// one lookup so Settings can never report an agent as ready that Connect then cannot find. The
/// file system is injected so the rules are testable without the owner's installs.
public struct ACPAgentResolver {
    let home: String
    let isExecutable: (String) -> Bool
    let exists: (String) -> Bool
    let contents: (String) -> [String]

    public init(home: String, isExecutable: @escaping (String) -> Bool, exists: @escaping (String) -> Bool,
                contents: @escaping (String) -> [String]) {
        self.home = home
        self.isExecutable = isExecutable
        self.exists = exists
        self.contents = contents
    }

    public static var system: ACPAgentResolver {
        let files = FileManager.default
        return ACPAgentResolver(home: files.homeDirectoryForCurrentUser.path,
                                isExecutable: { files.isExecutableFile(atPath: $0) },
                                exists: { files.fileExists(atPath: $0) },
                                contents: { (try? files.contentsOfDirectory(atPath: $0)) ?? [] })
    }

    /// Node version managers install global CLIs beside their own node, newest first.
    private var nodeBins: [String] {
        [home + "/.local/share/mise/installs/node", home + "/.nvm/versions/node"].flatMap { root in
            contents(root).sorted { $0.compare($1, options: .numeric) == .orderedDescending }.map { root + "/" + $0 + "/bin" }
        }
    }

    private var userFirst: [String] { [home + "/.local/bin", "/opt/homebrew/bin", "/usr/local/bin"] }

    private func find(_ names: [String], in directories: [String]? = nil) -> String? {
        for directory in (directories ?? userFirst) + nodeBins {
            for name in names where isExecutable(directory + "/" + name) { return directory + "/" + name }
        }
        return nil
    }

    public func launch(_ provider: ACPProvider) throws -> ACPLaunch {
        switch provider {
        case .claude, .codex:
            let package = provider == .claude ? "claude-agent-acp" : "codex-acp"
            let cli = provider == .claude ? "claude" : "codex"
            guard let installed = find([cli]) else {
                throw ACPResolutionError(state: .notInstalled, message: "Install and sign in to " + provider.title + " first.")
            }
            let adapter = home + "/.local/share/volant/acp/node_modules/@agentclientprotocol/" + package + "/dist/index.js"
            guard exists(adapter) else {
                throw ACPResolutionError(state: .needsAdapter, message: provider.title + "’s ACP adapter is missing. Install Volant’s ACP adapters and retry.")
            }
            guard let node = find(["node"], in: ["/opt/homebrew/bin", "/usr/local/bin", home + "/.local/bin"]) else {
                throw ACPResolutionError(state: .needsNode, message: "The ACP adapters require Node.js 22 or newer.")
            }
            return ACPLaunch(executable: node, arguments: [adapter],
                             environment: [provider == .claude ? "CLAUDE_CODE_EXECUTABLE" : "CODEX_PATH": installed])
        case .opencode:
            guard let installed = find(["opencode"], in: ["/opt/homebrew/bin", home + "/.opencode/bin", home + "/.local/bin", "/usr/local/bin"]) else {
                throw ACPResolutionError(state: .notInstalled, message: "OpenCode was not found. Install it and run opencode auth login, then retry.")
            }
            return ACPLaunch(executable: installed, arguments: ["acp"], environment: [:])
        case .cursor:
            guard let installed = find(["agent", "cursor-agent"]) else {
                throw ACPResolutionError(state: .notInstalled, message: "Cursor CLI is not installed. Install and sign in to Cursor CLI, then retry.")
            }
            return ACPLaunch(executable: installed, arguments: ["acp"], environment: [:])
        case .gemini, .qwen:
            let cli = provider == .gemini ? "gemini" : "qwen"
            guard let installed = find([cli]) else {
                throw ACPResolutionError(state: .notInstalled, message: provider.title + " was not found. Install it and sign in, then retry.")
            }
            return ACPLaunch(executable: installed, arguments: ["--acp"], environment: [:])
        }
    }

    /// Detection only looks at files; it never starts an agent, so it cannot tell whether the
    /// provider is signed in. The first connection does that.
    public func availability(_ provider: ACPProvider) -> ACPAgentAvailability {
        do {
            let launch = try launch(provider)
            let path = launch.environment.values.first ?? launch.executable
            return ACPAgentAvailability(provider: provider.rawValue, state: .ready, detail: "Found at " + abbreviate(path), path: path)
        } catch let error as ACPResolutionError {
            return ACPAgentAvailability(provider: provider.rawValue, state: error.state, detail: error.message, path: nil)
        } catch {
            return ACPAgentAvailability(provider: provider.rawValue, state: .notInstalled, detail: error.localizedDescription, path: nil)
        }
    }

    public func detectAll() -> [ACPAgentAvailability] { ACPProvider.allCases.map(availability) }

    private func abbreviate(_ path: String) -> String {
        path.hasPrefix(home + "/") ? "~" + path.dropFirst(home.count) : path
    }
}
