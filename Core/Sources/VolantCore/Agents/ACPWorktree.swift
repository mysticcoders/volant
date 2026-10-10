import Foundation

/// One git run: its exit status and standard output.
public struct GitResult: Equatable {
    public let status: Int32
    public let output: Data

    public init(status: Int32, output: Data) {
        self.status = status
        self.output = output
    }
}

/// The git worktree an isolated ACP conversation runs in, on its own `volant/<id>` branch under
/// `root`, so two agents, or an agent and the owner, start in separate checkouts.
///
/// Every git call that creates or removes a workspace ignores the system and global configuration
/// and turns off hooks and fsmonitor, so the hooks and fsmonitor that the repository or the owner
/// configured do not run. Ignoring the global configuration also keeps globally installed checkout
/// filters, such as the one Git LFS installs, from running: files they manage stay pointer files in
/// the workspace. A repository whose own configuration defines a filter, a hook or a conditional
/// include is refused, since those would still run. Removal reads one global setting, the owner's
/// excludes file, so files the owner ignores everywhere do not count as changes. A workspace
/// confines nothing: the agent in it keeps the owner's credentials and can reach any path.
public struct ACPWorktree {
    /// Runs git with arguments in a directory with an environment, returning exit status and stdout.
    public typealias Run = (_ arguments: [String], _ directory: String, _ environment: [String: String]) throws -> GitResult

    public let root: URL
    private let home: String
    private let run: Run

    public init(root: URL, home: String, run: @escaping Run) {
        self.root = root
        self.home = home
        self.run = run
    }

    /// One workspace is created or removed at a time in this process. Each helper connection has its
    /// own queue, and two `worktree add --track` runs on one repository race for the lock on its
    /// configuration file.
    private static let lock = NSLock()

    /// Prefixed to every call. Settings given on the command line take precedence over the
    /// repository's own, so its configuration cannot turn these back on.
    static let isolation = ["-c", "core.fsmonitor=false", "-c", "core.hooksPath=/dev/null"]

    /// Configuration keys that refuse a repository. A filter runs when files are checked out or
    /// compared, and a hook set with `hook.<name>.command` (git 2.54 and later) runs regardless of
    /// `core.hooksPath`. A conditional include can add either where Volant doesn't read it, for
    /// example only on the new branch, so every conditional include is refused.
    static let refusedSettings = "^(filter|hook|includeif)\\."

    /// The status command's environment, without the system configuration and with an empty global one.
    var environment: [String: String] {
        RepositoryStatusCommand.environment(home: home).merging(["GIT_CONFIG_NOSYSTEM": "1", "GIT_CONFIG_GLOBAL": "/dev/null"]) { $1 }
    }

    /// Makes a worktree of the repository at `project` on a new `volant/<id>` branch and returns its
    /// path with symlinks resolved. The branch starts from the project's current branch and tracks
    /// it, so the workspace reports how far it is ahead; from a detached HEAD it starts at that
    /// commit and tracks nothing.
    public func create(project: String, id: String) throws -> String {
        guard Self.isValidID(id) else { throw Self.failure("This workspace name is not valid.") }
        // An empty project is general chat, which has no repository to copy.
        guard !project.isEmpty, let source = try? ACPWorkingDirectory.resolve(project: project, generalChat: root) else {
            throw Self.failure("Choose a working folder that exists to use an isolated workspace.")
        }
        Self.lock.lock(); defer { Self.lock.unlock() }
        // Read before the first status, which can run a filter on a file whose timestamp changed.
        guard try !definesRefusedSettings(in: source) else {
            throw Self.failure("This repository’s own Git settings define a filter, a hook or a conditional include. Volant doesn’t run them, so it won’t create an isolated workspace here.")
        }
        guard let state = try status(in: source) else {
            throw Self.failure("The working folder isn’t a Git repository, so Volant can’t create an isolated workspace for it.")
        }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let path = root.appendingPathComponent(Self.folderName(project: source, id: id), isDirectory: true).path
        // Attributes are read without following a final symlink, so a dangling link counts too.
        guard (try? FileManager.default.attributesOfItem(atPath: path)) == nil else {
            throw Self.failure("Something already exists at " + path + ". Volant won’t replace it.")
        }
        let branch = "volant/" + id
        guard try !hasBranch(branch, in: source) else {
            throw Self.failure("This repository already has a branch named " + branch + ". Try again.")
        }
        let start = state.branch.map { ["--track", "-b", branch, path, "refs/heads/" + $0] } ?? ["-b", branch, path, "HEAD"]
        // A run whose output Volant couldn't read may still have made the whole workspace.
        let added = (try? git(["worktree", "add", "--quiet"] + start, in: source))?.status == 0
        if added || (FileManager.default.fileExists(atPath: path) && (try? status(in: path))?.branch == branch) {
            return URL(fileURLWithPath: path).resolvingSymlinksInPath().path
        }
        throw leftovers(path: path, branch: branch, in: source)
    }

    /// Removes a workspace under `root` that has no change, staged, unstaged or untracked, and
    /// returns its branch, which stays with its commits. Returns nil when no folder is left at `path`,
    /// so there is nothing to remove. Ignored files, such as build output, are deleted with it. Git's
    /// own checks still apply: a locked workspace or one with submodules is refused, since `--force`
    /// is never passed.
    public func remove(path: String) throws -> String? {
        guard Self.isInside(path, root: root) else { throw Self.failure("Volant removes only workspaces it created.") }
        Self.lock.lock(); defer { Self.lock.unlock() }
        var directory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: path, isDirectory: &directory), directory.boolValue else { return nil }
        let workspace = URL(fileURLWithPath: path).resolvingSymlinksInPath().path
        // The agent or the owner may have added such settings since the workspace was made.
        guard try !definesRefusedSettings(in: workspace) else {
            throw Self.failure("This workspace’s Git settings define a filter, a hook or a conditional include. Volant doesn’t run them, so it won’t remove the workspace. Remove it with git worktree remove.")
        }
        let excludes = try ownerExcludes(in: workspace)
        guard let state = try status(in: workspace, settings: excludes) else { throw Self.failure("This folder isn’t a Git workspace.") }
        guard state.changed == 0 else {
            throw Self.failure("This workspace has uncommitted or untracked changes. Commit or discard them first.")
        }
        // Commits made on a detached HEAD would be on no branch once the workspace is gone.
        guard let branch = state.branch else {
            throw Self.failure("This workspace isn’t on a branch, so removing it could lose commits. Check out a branch in it first.")
        }
        let common = try git(["rev-parse", "--path-format=absolute", "--git-common-dir"], in: workspace)
        let gitDirectory = String(decoding: common.output, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        guard common.status == 0, gitDirectory.hasPrefix("/") else {
            throw Self.failure("Couldn’t find the repository this workspace belongs to.")
        }
        // Run from the repository's git folder, which works for a `.git` folder, a bare repository, a
        // submodule's folder under `.git/modules` and a separate git directory alike.
        guard try git(excludes + ["worktree", "remove", workspace], in: gitDirectory).status == 0 else {
            throw Self.failure("Git couldn’t remove the workspace. It may be locked or hold a submodule.")
        }
        return branch
    }

    /// Eight lowercase hexadecimal characters.
    public static func newID() -> String {
        String(UUID().uuidString.lowercased().filter { $0 != "-" }.prefix(8))
    }

    static func isValidID(_ id: String) -> Bool {
        id.utf8.count == 8 && id.utf8.allSatisfy { (0x30...0x39).contains($0) || (0x61...0x66).contains($0) }
    }

    /// Whether `path` is below `root` once symlinks and `..` are resolved, so a link or a relative
    /// step cannot point removal at a folder outside it.
    public static func isInside(_ path: String, root: URL) -> Bool {
        guard path.hasPrefix("/"), !path.contains("\0") else { return false }
        let base = root.resolvingSymlinksInPath().standardizedFileURL.path
        let target = URL(fileURLWithPath: path).resolvingSymlinksInPath().standardizedFileURL.path
        return target.hasPrefix(base + "/")
    }

    /// The project folder's name, reduced to `[A-Za-z0-9._-]` and 64 characters, then the ID. The
    /// name is decomposed first, since macOS returns path components decomposed and Linux does not,
    /// so "Über" becomes "U-ber" on both.
    static func folderName(project: String, id: String) -> String {
        let allowed = Set("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789._-".unicodeScalars)
        var name = ""
        for scalar in URL(fileURLWithPath: project).lastPathComponent.decomposedStringWithCanonicalMapping.unicodeScalars.prefix(64) {
            name.unicodeScalars.append(allowed.contains(scalar) ? scalar : "-")
        }
        return (name.isEmpty ? "workspace" : name) + "-" + id
    }

    private func git(_ arguments: [String], in directory: String) throws -> GitResult {
        try run(Self.isolation + arguments, directory, environment)
    }

    /// Nil when the folder is not a repository or git fails there. `settings` are `-c` pairs placed
    /// before the status arguments.
    private func status(in directory: String, settings: [String] = []) throws -> RepositoryState? {
        let result = try git(settings + RepositoryStatusCommand.arguments, in: directory)
        guard result.status == 0 else { return nil }
        return RepositoryState.parse(porcelainV2: String(decoding: result.output, as: UTF8.self))
    }

    /// Read without a scope and with the system and global files off, this is the repository's own
    /// configuration, its per-worktree configuration and every file they include, conditionally or
    /// not. Exit status 1 means no key matched; any other failure refuses.
    private func definesRefusedSettings(in directory: String) throws -> Bool {
        let result = try git(["config", "--includes", "--name-only", "--get-regexp", Self.refusedSettings], in: directory)
        guard result.status == 0 || result.status == 1 else { throw Self.failure("Couldn’t read this repository’s Git settings.") }
        return result.status == 0
    }

    private func hasBranch(_ branch: String, in directory: String) throws -> Bool {
        try git(["rev-parse", "--verify", "--quiet", "refs/heads/" + branch], in: directory).status == 0
    }

    /// The owner's global `core.excludesFile` as a `-c` pair, so removal treats as ignored the files
    /// the owner's own `git status` ignores. Reading a setting runs no program, and the system
    /// configuration stays off. Without one set, git reads its default global ignore file in any case.
    private func ownerExcludes(in directory: String) throws -> [String] {
        let result = try run(Self.isolation + ["config", "--global", "--includes", "--path", "--get", "core.excludesFile"], directory,
                             RepositoryStatusCommand.environment(home: home).merging(["GIT_CONFIG_NOSYSTEM": "1"]) { $1 })
        let file = String(decoding: result.output, as: UTF8.self).trimmingCharacters(in: .newlines)
        return result.status == 0 && !file.isEmpty ? ["-c", "core.excludesFile=" + file] : []
    }

    /// Git makes the branch before the worktree, and a run stopped at its deadline can leave a partly
    /// written folder. A branch this call made with no folder beside it is deleted with `branch -d`,
    /// which refuses a branch with commits of its own; whatever remains is named.
    private func leftovers(path: String, branch: String, in source: String) -> NSError {
        let folder = (try? FileManager.default.attributesOfItem(atPath: path)) != nil
        var branchLeft = (try? hasBranch(branch, in: source)) ?? true
        if branchLeft, !folder {
            _ = try? git(["branch", "-d", branch], in: source)
            branchLeft = (try? hasBranch(branch, in: source)) ?? true
        }
        let left = (folder ? ["the folder " + path] : []) + (branchLeft ? ["the branch " + branch] : [])
        guard !left.isEmpty else {
            return Self.failure("Git couldn’t create the workspace. Check that the repository has at least one commit and no branch named volant.")
        }
        return Self.failure("Git couldn’t create the workspace and left " + left.joined(separator: " and ") + ".")
    }

    private static func failure(_ message: String) -> NSError {
        NSError(domain: "VolantWorktree", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
    }
}
