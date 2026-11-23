#if os(macOS)
import Foundation

/// What the helper reports after removing a worktree: its path and, when it had uncommitted work,
/// the folder that work was saved to.
public struct WorktreeRemoval: Codable, Hashable {
    public let path: String
    public let backup: String?

    public init(path: String, backup: String?) { self.path = path; self.backup = backup }
}

/// The request the app sends: the worktree as its row showed it.
public struct WorktreeRemovalRequest: Codable, Hashable {
    public let repository: String
    public let path: String
    public let head: String

    public init(repository: String, path: String, head: String) { self.repository = repository; self.path = path; self.head = head }
}

/// Removes one linked worktree, or prunes a repository's stale records, for the Worktrees command's
/// phase 2 (docs/worktrees-command.md). Everything is rechecked against git right before acting:
/// the path must still be a linked, unlocked worktree of that repository at the commit the row
/// showed, no process may be working inside it, and its commits must be reachable from a branch or
/// remote. Uncommitted work is saved first; if that fails, nothing is removed. Branches are never
/// deleted and the main working folder is never touched.
public struct WorktreeRemover {
    /// Runs git with these arguments in this folder, allowing this many seconds, and returns its
    /// output, or nil when it failed.
    public typealias Git = (_ arguments: [String], _ directory: String, _ timeout: TimeInterval) -> Data?

    public static let maximumBackupBytes: Int64 = 100_000_000
    public static let maximumBackupFiles = 10_000

    let git: Git
    let backupRoot: String
    let processesInside: (String) -> [String]
    let now: () -> Date

    /// `backupRoot` is the folder dated backup folders go in, normally
    /// `~/Library/Application Support/Volant/Worktree Backups`.
    public init(git: @escaping Git, backupRoot: String, processesInside: @escaping (String) -> [String] = { ListeningServers.processes(workingInside: $0) },
                now: @escaping () -> Date = Date.init) {
        self.git = git; self.backupRoot = backupRoot; self.processesInside = processesInside; self.now = now
    }

    /// Whether `value` looks like a full commit ID (SHA-1 or SHA-256).
    public static func isCommit(_ value: String) -> Bool {
        (value.count == 40 || value.count == 64) && value.allSatisfy { $0.isHexDigit && !$0.isUppercase }
    }

    /// Rechecks, backs up and removes the worktree, or throws a `HostMessage` saying why not.
    public func remove(_ request: WorktreeRemovalRequest) throws -> WorktreeRemoval {
        let path = request.path, repository = request.repository
        guard path.hasPrefix("/"), repository.hasPrefix("/"), path != repository, !path.contains("\0"), !repository.contains("\0"),
              Self.isCommit(request.head) else { throw HostMessage(.worktreeChanged) }
        guard Worktrees.repository(ofWorktree: path) == repository,
              let listed = git(["worktree", "list", "--porcelain", "-z"], repository, 5),
              let entry = Worktrees.parse(porcelain: listed).first(where: { $0.path == path }),
              entry.repository == repository, entry.head == request.head, !entry.stale else { throw HostMessage(.worktreeChanged) }
        guard !entry.locked else { throw HostMessage(.worktreeLocked) }
        if let holder = processesInside(path).first { throw HostMessage(.worktreeInUse, holder) }
        guard let unreachable = git(["rev-list", "-n", "1", "HEAD", "--not", "--branches", "--remotes"], path, 10) else {
            throw HostMessage(.worktreeChanged)
        }
        guard unreachable.isEmpty else { throw HostMessage(.worktreeUnreachable) }
        guard let status = git(["status", "--porcelain=v1", "-z", "--untracked-files=normal", "--ignore-submodules=all"], path, 15) else {
            throw HostMessage(.worktreeBackupFailed)
        }
        let backup = status.isEmpty ? nil : try save(entry)
        guard git(["worktree", "remove", "--force", path], repository, 120) != nil else { throw HostMessage(.worktreeRemoveFailed) }
        return WorktreeRemoval(path: path, backup: backup)
    }

    /// Runs `git worktree prune` in a repository that keeps worktree records, returning how many
    /// stale records went away.
    public func prune(repository: String) throws -> Int {
        guard repository.hasPrefix("/"), !repository.contains("\0"), Worktrees.hasWorktrees(repository),
              Worktrees.repository(containing: repository) == repository else { throw HostMessage(.worktreeChanged) }
        let stale = { (self.git(["worktree", "list", "--porcelain", "-z"], repository, 5)).map { Worktrees.parse(porcelain: $0).filter(\.stale).count } }
        guard let before = stale(), git(["worktree", "prune"], repository, 30) != nil, let after = stale() else { throw HostMessage(.worktreePruneFailed) }
        return max(0, before - after)
    }

    /// A new folder under `backupRoot/<date>/` named for the repository and worktree, with a number
    /// added when one by that name exists.
    public static func backupFolder(root: String, date: Date, repository: String, name: String, exists: (String) -> Bool) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX"); formatter.dateFormat = "yyyy-MM-dd"
        let safe = { (text: String) in String(text.map { $0 == "/" || $0 == ":" ? "-" : $0 }) }
        let base = (root as NSString).appendingPathComponent(formatter.string(from: date)) + "/" + safe((repository as NSString).lastPathComponent) + "-" + safe(name)
        var candidate = base, number = 2
        while exists(candidate) { candidate = base + "-\(number)"; number += 1 }
        return candidate
    }

    /// Saves tracked changes as `changes.patch` and untracked, unignored files under `untracked/`,
    /// with a README saying where they came from. Deletes the partial folder and throws on failure.
    func save(_ entry: Worktree) throws -> String {
        let fm = FileManager.default
        let folder = Self.backupFolder(root: backupRoot, date: now(), repository: entry.repository, name: entry.name) { fm.fileExists(atPath: $0) }
        do {
            try fm.createDirectory(atPath: folder, withIntermediateDirectories: true)
            let patch = (folder as NSString).appendingPathComponent("changes.patch")
            guard git(["diff", "HEAD", "--binary", "--output=" + patch], entry.path, 60) != nil else { throw HostMessage(.worktreeBackupFailed) }
            guard let listed = git(["ls-files", "--others", "--exclude-standard", "-z"], entry.path, 30) else { throw HostMessage(.worktreeBackupFailed) }
            let files = String(decoding: listed, as: UTF8.self).split(separator: "\0").map(String.init)
            guard files.count <= Self.maximumBackupFiles else { throw HostMessage(.worktreeBackupTooLarge) }
            var total = (try? fm.attributesOfItem(atPath: patch)[.size] as? Int64) ?? 0
            for file in files {
                guard !file.hasPrefix("/"), !file.split(separator: "/").contains("..") else { throw HostMessage(.worktreeBackupFailed) }
                let source = (entry.path as NSString).appendingPathComponent(file)
                let attributes = try fm.attributesOfItem(atPath: source)
                total += (attributes[.size] as? Int64) ?? 0
                guard total <= Self.maximumBackupBytes else { throw HostMessage(.worktreeBackupTooLarge) }
                let target = ((folder as NSString).appendingPathComponent("untracked") as NSString).appendingPathComponent(file)
                try fm.createDirectory(atPath: (target as NSString).deletingLastPathComponent, withIntermediateDirectories: true)
                try fm.copyItem(atPath: source, toPath: target)
            }
            let checkout = entry.branch.map { "branch " + $0 } ?? "detached at " + (entry.head ?? "unknown")
            let readme = """
            Uncommitted work saved by Volant before removing a git worktree.

            Repository: \(entry.repository)
            Worktree: \(entry.path)
            Checkout: \(checkout)
            Commit: \(entry.head ?? "unknown")

            changes.patch holds changes to tracked files: git apply --binary changes.patch
            untracked/ holds files git wasn't tracking, at their paths in the worktree.

            """
            try readme.write(toFile: (folder as NSString).appendingPathComponent("README.txt"), atomically: true, encoding: .utf8)
            return folder
        } catch {
            try? fm.removeItem(atPath: folder)
            throw (error as? HostMessage) ?? HostMessage(.worktreeBackupFailed)
        }
    }
}
#endif
