import Foundation
import VolantCore

/// Runs `RepositoryStatusCommand` in the folders local agents are working in, with a short
/// timeout and bounded output, and the fixed worktree commands of `ACPWorktree` for isolated
/// conversations. Nothing else is executed.
enum RepositoryInspector {
    /// Folders that are missing, relative or not repositories are left out of the result rather
    /// than reported as errors, since most agent panes share a handful of repositories.
    static func states(for paths: [String]) throws -> [String: RepositoryState] {
        guard paths.count <= RepositoryStateLimit.paths else { throw CocoaError(.fileReadTooLarge) }
        guard let git = RepositoryStatusCommand.git() else { return [:] }
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        var result: [String: RepositoryState] = [:]
        for path in Set(paths) where path.hasPrefix("/") && !path.contains("\0") {
            var directory: ObjCBool = false
            guard FileManager.default.fileExists(atPath: path, isDirectory: &directory), directory.boolValue,
                  let output = try? HerdrProcess.run(executable: URL(fileURLWithPath: git), arguments: RepositoryStatusCommand.arguments,
                                                     home: home, timeout: 3, directory: path,
                                                     environment: RepositoryStatusCommand.environment(home: home)),
                  let state = RepositoryState.parse(porcelainV2: String(decoding: output, as: UTF8.self)) else { continue }
            result[path] = state
        }
        return result
    }

    /// Isolated workspaces under `~/Library/Application Support/Volant/Worktrees`, beside the general
    /// chat folder, made with the same git and bounded process as status reads. A git call that
    /// runs past two minutes is stopped; a large checkout needs more than the status read's 3 s.
    static func worktrees() throws -> ACPWorktree {
        guard let git = RepositoryStatusCommand.git() else {
            throw NSError(domain: "VolantWorktree", code: 2, userInfo: [NSLocalizedDescriptionKey:
                "Git was not found. Install the Command Line Tools or Git, then try again."])
        }
        let home = FileManager.default.homeDirectoryForCurrentUser
        let root = home.appendingPathComponent("Library/Application Support/Volant/Worktrees", isDirectory: true)
        return ACPWorktree(root: root, home: home.path) { arguments, directory, environment in
            do {
                let result = try HerdrProcess.runStatus(executable: URL(fileURLWithPath: git), arguments: arguments, home: home.path,
                                                        timeout: 120, directory: directory, environment: environment)
                return GitResult(status: result.status, output: result.output)
            } catch {
                throw NSError(domain: "VolantWorktree", code: 3, userInfo: [NSLocalizedDescriptionKey:
                    "Git didn’t finish within two minutes, or Volant couldn’t read its output. Try again."])
            }
        }
    }
}
