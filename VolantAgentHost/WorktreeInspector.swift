import Foundation
import VolantCore

/// Reads the owner's git worktrees for the Worktrees command: lists them with `git worktree list`
/// and measures them, with short timeouts and bounded input. Nothing is changed, logged or kept.
enum WorktreeInspector {
    /// Validates the app's folder hints, adds listening servers' folders, and lists every linked
    /// worktree of the repositories found.
    static func list(folders data: Data) throws -> [Worktree] {
        guard data.count <= 128_000 else { throw CocoaError(.fileReadTooLarge) }
        let hints = try validated(JSONDecoder().decode([String].self, from: data), limit: Worktrees.maximumFolders)
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let servers = ListeningServers.scan().compactMap(\.directory)
        return Worktrees.list(roots: Worktrees.defaultRoots(home: home), folders: hints + servers) { arguments, directory in
            git(arguments, in: directory, home: home)
        }
    }

    /// Size and last commit for each requested path that is still a linked worktree.
    static func details(paths data: Data) throws -> [String: WorktreeDetails] {
        guard data.count <= 16_000 else { throw CocoaError(.fileReadTooLarge) }
        let paths = try validated(JSONDecoder().decode([String].self, from: data), limit: Worktrees.maximumDetailPaths)
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        var result: [String: WorktreeDetails] = [:]
        for path in Set(paths) where Worktrees.repository(ofWorktree: path) != nil {
            let size = Worktrees.size(of: path, deadline: Date().addingTimeInterval(6))
            let committed = git(["log", "-1", "--format=%ct", "HEAD"], in: path, home: home)
                .flatMap { TimeInterval(String(decoding: $0, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)) }
                .map { Date(timeIntervalSince1970: $0) }
            result[path] = WorktreeDetails(size: size.bytes, sizeComplete: size.complete, lastCommit: committed)
        }
        return result
    }

    /// Absolute paths only, without NUL bytes or extreme lengths, at most `limit`.
    static func validated(_ paths: [String], limit: Int) throws -> [String] {
        guard paths.count <= limit, paths.allSatisfy({ $0.hasPrefix("/") && !$0.contains("\0") && $0.utf8.count <= 1024 }) else {
            throw CocoaError(.fileReadInvalidFileName)
        }
        return paths
    }

    /// Runs git in `directory` with the same locked-down settings as the change counts, or nil.
    static func git(_ arguments: [String], in directory: String, home: String) -> Data? {
        guard let git = RepositoryStatusCommand.git() else { return nil }
        return try? HerdrProcess.run(executable: URL(fileURLWithPath: git), arguments: ["-c", "core.fsmonitor=false", "--no-optional-locks"] + arguments,
                                     home: home, timeout: 3, directory: directory, environment: RepositoryStatusCommand.environment(home: home))
    }
}
