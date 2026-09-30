import Foundation

/// The most working folders one request may ask about; the app and the helper both enforce it.
public enum RepositoryStateLimit {
    public static let paths = 32
}

/// The one git command the helper may run for change counts. No optional locks, so an agent in
/// the middle of a commit is never blocked; fsmonitor off, so a repository's own configuration
/// cannot make Volant launch a program; submodules ignored, so a large tree stays fast.
/// `/usr/bin/git` is never chosen: without the Command Line Tools that stub opens an installer
/// dialog instead of running.
public enum RepositoryStatusCommand {
    public static let arguments = ["-c", "core.fsmonitor=false", "--no-optional-locks", "status", "--porcelain=v2", "--branch",
                                   "--untracked-files=normal", "--ignore-submodules=all"]

    public static func git(isExecutable: (String) -> Bool = { FileManager.default.isExecutableFile(atPath: $0) }) -> String? {
        ["/opt/homebrew/bin/git", "/usr/local/bin/git", "/Library/Developer/CommandLineTools/usr/bin/git",
         "/Applications/Xcode.app/Contents/Developer/usr/bin/git"].first(where: isExecutable)
    }

    public static func environment(home: String) -> [String: String] {
        ["HOME": home, "PATH": "/usr/bin:/bin", "LC_ALL": "C", "GIT_OPTIONAL_LOCKS": "0", "GIT_TERMINAL_PROMPT": "0"]
    }
}

/// Counts from one `git status --porcelain=v2 --branch` run. Only counts and the branch name are
/// kept; file names are read on demand and never stored.
public struct RepositoryState: Codable, Equatable {
    public var branch: String?
    public var ahead = 0
    public var behind = 0
    public var changed = 0

    public init(branch: String? = nil, ahead: Int = 0, behind: Int = 0, changed: Int = 0) {
        self.branch = branch
        self.ahead = ahead
        self.behind = behind
        self.changed = changed
    }

    /// Returns nil for output that does not start with branch headers, which is what git prints
    /// outside a repository or when the format is not the one requested.
    public static func parse(porcelainV2 output: String) -> RepositoryState? {
        var state = RepositoryState()
        var sawBranch = false
        for line in output.split(separator: "\n", omittingEmptySubsequences: true) {
            if line.hasPrefix("# branch.head ") {
                sawBranch = true
                let head = String(line.dropFirst("# branch.head ".count))
                state.branch = head == "(detached)" ? nil : head
            } else if line.hasPrefix("# branch.ab ") {
                for part in line.dropFirst("# branch.ab ".count).split(separator: " ") {
                    if part.hasPrefix("+") { state.ahead = Int(part.dropFirst()) ?? 0 }
                    if part.hasPrefix("-") { state.behind = Int(part.dropFirst()) ?? 0 }
                }
            } else if let kind = line.first, "12u?".contains(kind), line.dropFirst().first == " " {
                state.changed += 1
            }
        }
        return sawBranch ? state : nil
    }

    /// "main · 3 changed · 2 ahead", leaving out whatever is zero.
    public var summary: String {
        var parts = [branch ?? "detached"]
        if changed > 0 { parts.append("\(changed) changed") }
        if ahead > 0 { parts.append("\(ahead) ahead") }
        if behind > 0 { parts.append("\(behind) behind") }
        if changed == 0 && ahead == 0 && behind == 0 { parts.append("clean") }
        return parts.joined(separator: " · ")
    }
}
