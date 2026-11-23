#if os(macOS)
import Foundation

/// A linked git worktree of one of the owner's repositories, from `git worktree list --porcelain`.
/// Read by the agent helper, which can run git outside App Sandbox. Carries paths, the branch name
/// and the commit, never file contents. See docs/worktrees-command.md.
public struct Worktree: Codable, Hashable, Identifiable {
    /// The repository's main working folder, which git lists first.
    public let repository: String
    public let path: String
    /// The checked-out branch's short name, or nil when HEAD is detached.
    public let branch: String?
    /// The full commit at HEAD, when git reported one.
    public let head: String?
    /// Whether someone ran `git worktree lock` on it.
    public let locked: Bool
    /// Whether git marks it prunable: registered, but its folder is gone.
    public let stale: Bool

    public var id: String { path }
    public var name: String { (path as NSString).lastPathComponent }
    public var repositoryName: String { (repository as NSString).lastPathComponent }
    public var shortHead: String? { head.map { String($0.prefix(7)) } }
    /// The row's first line: the folder name and the branch, or `detached` with the short commit.
    public var title: String {
        let checkout = branch ?? ["detached", shortHead].compactMap { $0 }.joined(separator: " ")
        return name + " · " + checkout
    }

    public init(repository: String, path: String, branch: String?, head: String?, locked: Bool = false, stale: Bool = false) {
        self.repository = repository; self.path = path; self.branch = branch
        self.head = head; self.locked = locked; self.stale = stale
    }

    /// The path with the home folder shortened to `~`.
    public func abbreviatedPath(home: String) -> String { Worktrees.abbreviate(path, home: home) }
}

/// What the helper measures for one worktree after listing it: allocated size on disk, whether the
/// walk finished within its limits, and when HEAD was committed.
public struct WorktreeDetails: Codable, Hashable {
    public var size: Int64?
    /// False when the walk stopped at its time or file limit, so `size` is a lower bound.
    public var sizeComplete: Bool
    public var lastCommit: Date?

    public init(size: Int64?, sizeComplete: Bool = true, lastCommit: Date? = nil) {
        self.size = size; self.sizeComplete = sizeComplete; self.lastCommit = lastCommit
    }
}

/// The Worktrees command: its query words, parsing, ordering and, for the helper, finding
/// repositories and measuring worktrees.
public enum Worktrees {
    public static let maximumRepositories = 64
    public static let maximumWorktrees = 256
    /// The most folders the app may pass as hints, and the most paths one details request carries.
    public static let maximumFolders = 64
    public static let maximumDetailPaths = 4
    public static let queryWords = ["worktrees", "worktree", "wt"]
    /// Folders under the home folder searched for repositories, when they exist.
    public static let rootNames = ["workspace", "Developer", "src", "code", "Projects", "GitHub", "git", "repos"]
    /// How deep below a root the search looks for a repository's `.git` folder.
    public static let searchDepth = 4
    static let skippedFolders: Set<String> = ["node_modules", "Library", "build", "dist", "DerivedData", "Pods", "vendor", "target", ".build"]

    /// What follows a Worktrees query word, or nil when `query` isn't a Worktrees query. `stale` as
    /// the first word shows only stale entries.
    public static func queryTerm(_ query: String) -> (text: String, staleOnly: Bool)? {
        let value = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        for word in queryWords {
            let rest: String
            if value == word { rest = "" } else if value.hasPrefix(word + " ") { rest = String(value.dropFirst(word.count + 1)) } else { continue }
            let trimmed = rest.trimmingCharacters(in: .whitespaces)
            if trimmed == "stale" { return ("", true) }
            if trimmed.hasPrefix("stale ") { return (String(trimmed.dropFirst(6)).trimmingCharacters(in: .whitespaces), true) }
            return (trimmed, false)
        }
        return nil
    }

    /// The linked worktrees in `git worktree list --porcelain -z` output, leaving out the first
    /// (main) entry and bare repositories. Records are NUL-terminated lines separated by an empty one.
    public static func parse(porcelain data: Data) -> [Worktree] {
        let fields = String(decoding: data, as: UTF8.self).components(separatedBy: "\0")
        var records: [[String]] = [], current: [String] = []
        for field in fields {
            if field.isEmpty { if !current.isEmpty { records.append(current) }; current = [] } else { current.append(field) }
        }
        if !current.isEmpty { records.append(current) }
        guard let main = records.first?.first(where: { $0.hasPrefix("worktree ") }).map({ String($0.dropFirst(9)) }) else { return [] }
        return records.dropFirst().compactMap { record in
            var path: String?, head: String?, branch: String?, locked = false, stale = false, bare = false
            for line in record {
                if line.hasPrefix("worktree ") { path = String(line.dropFirst(9)) }
                else if line.hasPrefix("HEAD ") { head = String(line.dropFirst(5)) }
                else if line.hasPrefix("branch ") {
                    let ref = String(line.dropFirst(7))
                    branch = ref.hasPrefix("refs/heads/") ? String(ref.dropFirst(11)) : ref
                }
                else if line == "bare" { bare = true }
                else if line == "locked" || line.hasPrefix("locked ") { locked = true }
                else if line == "prunable" || line.hasPrefix("prunable ") { stale = true }
            }
            guard let path, path.hasPrefix("/"), !bare else { return nil }
            return Worktree(repository: main, path: path, branch: branch, head: head, locked: locked, stale: stale)
        }
    }

    /// Whether `path` is `folder` or inside it, comparing whole path components.
    public static func contains(_ folder: String, _ path: String) -> Bool {
        let base = folder.hasSuffix("/") ? String(folder.dropLast()) : folder
        return path == base || path.hasPrefix(base + "/")
    }

    /// Who is working in `worktree`: the first holder whose folder is inside it, as a label such as
    /// `Node.js on 3000` or `Rex: agents`. Holders are (folder, label) pairs the app gathers from
    /// listening servers and agent panes it already knows about.
    public static func holder(of worktree: Worktree, among holders: [(folder: String, label: String)]) -> String? {
        holders.first { contains(worktree.path, $0.folder) }?.label
    }

    /// Stale entries apart from the rest; the rest by size, largest first, unknown sizes after,
    /// then by path. Text matches the repository, branch or path. `staleOnly` keeps only stale ones.
    public static func arrange(_ worktrees: [Worktree], sizes: [String: Int64] = [:], matching text: String = "", staleOnly: Bool = false) -> [Worktree] {
        let term = text.trimmingCharacters(in: .whitespaces)
        return worktrees
            .filter { !staleOnly || $0.stale }
            .filter { item in
                term.isEmpty || item.repositoryName.localizedCaseInsensitiveContains(term) || item.path.localizedCaseInsensitiveContains(term)
                    || (item.branch?.localizedCaseInsensitiveContains(term) ?? false)
            }
            .sorted { a, b in
                if a.stale != b.stale { return !a.stale }
                let sa = sizes[a.path] ?? -1, sb = sizes[b.path] ?? -1
                return sa != sb ? sa > sb : a.path < b.path
            }
    }

    /// `path` with the home folder shortened to `~`.
    public static func abbreviate(_ path: String, home: String) -> String {
        let base = home.hasSuffix("/") ? String(home.dropLast()) : home
        if path == base { return "~" }
        return path.hasPrefix(base + "/") ? "~" + path.dropFirst(base.count) : path
    }

    /// How long ago, as `45s`, `12m`, `3h`, `5d` or `2w`.
    public static func age(of date: Date, now: Date = Date()) -> String {
        let seconds = max(0, Int(now.timeIntervalSince(date)))
        if seconds < 60 { return "\(seconds)s" }
        if seconds < 3600 { return "\(seconds / 60)m" }
        if seconds < 86400 { return "\(seconds / 3600)h" }
        if seconds < 86400 * 14 { return "\(seconds / 86400)d" }
        return "\(seconds / (86400 * 7))w"
    }

    /// A byte count the way Finder shows file sizes.
    public static func formatSize(_ bytes: Int64, complete: Bool = true) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file) + (complete ? "" : "+")
    }

    /// The repository a worktree folder belongs to, read from its `.git` file (`gitdir:
    /// <repo>/.git/worktrees/<name>`), or nil when the folder is not a linked worktree. A
    /// submodule's `.git` file points into `.git/modules/` and is not a worktree.
    public static func repository(ofWorktree path: String) -> String? {
        guard let gitdir = gitdir(in: path), let range = gitdir.range(of: "/.git/worktrees/") else { return nil }
        return String(gitdir[..<range.lowerBound])
    }

    static func gitdir(in folder: String) -> String? {
        let file = (folder as NSString).appendingPathComponent(".git")
        var directory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: file, isDirectory: &directory), !directory.boolValue,
              let attributes = try? FileManager.default.attributesOfItem(atPath: file),
              (attributes[.size] as? Int ?? 0) < 4096,
              let text = try? String(contentsOfFile: file, encoding: .utf8) else { return nil }
        guard let line = text.split(separator: "\n").first, line.hasPrefix("gitdir: ") else { return nil }
        let target = String(line.dropFirst(8)).trimmingCharacters(in: .whitespaces)
        return target.hasPrefix("/") ? target : URL(fileURLWithPath: (folder as NSString).appendingPathComponent(target)).standardized.path
    }

    /// The repository holding `folder`: walks up to the nearest `.git`. A `.git` folder marks a
    /// main working folder; a `.git` file of a linked worktree leads to its repository; a
    /// submodule's leads nowhere.
    public static func repository(containing folder: String) -> String? {
        var current = URL(fileURLWithPath: folder).standardized.path
        while current.count > 1 {
            var directory: ObjCBool = false
            let git = (current as NSString).appendingPathComponent(".git")
            if FileManager.default.fileExists(atPath: git, isDirectory: &directory) {
                return directory.boolValue ? current : repository(ofWorktree: current)
            }
            current = (current as NSString).deletingLastPathComponent
        }
        return nil
    }

    /// Whether git keeps linked-worktree records for the repository at `path`.
    public static func hasWorktrees(_ path: String) -> Bool {
        var directory: ObjCBool = false
        let records = (path as NSString).appendingPathComponent(".git/worktrees")
        return FileManager.default.fileExists(atPath: records, isDirectory: &directory) && directory.boolValue
    }

    /// Repositories with linked worktrees: those under `roots` to `searchDepth`, skipping hidden,
    /// dependency and build folders, plus those holding any of `folders`. At most
    /// `maximumRepositories`, in a stable order.
    public static func repositories(roots: [String], folders: [String]) -> [String] {
        var found: [String] = [], seen = Set<String>()
        func add(_ repo: String) {
            guard found.count < maximumRepositories, seen.insert(repo).inserted, hasWorktrees(repo) else { return }
            found.append(repo)
        }
        for folder in folders.prefix(maximumFolders) where folder.hasPrefix("/") {
            if let repo = repository(containing: folder) { add(repo) }
        }
        func walk(_ folder: String, depth: Int) {
            guard found.count < maximumRepositories else { return }
            var directory: ObjCBool = false
            if FileManager.default.fileExists(atPath: (folder as NSString).appendingPathComponent(".git"), isDirectory: &directory) {
                if directory.boolValue { add(folder) }
                return
            }
            guard depth < searchDepth, let names = try? FileManager.default.contentsOfDirectory(atPath: folder) else { return }
            for name in names.sorted() where !name.hasPrefix(".") && !skippedFolders.contains(name) {
                let child = (folder as NSString).appendingPathComponent(name)
                guard let values = try? URL(fileURLWithPath: child).resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey, .isPackageKey]),
                      values.isDirectory == true, values.isSymbolicLink != true, values.isPackage != true else { continue }
                walk(child, depth: depth + 1)
            }
        }
        for root in roots { walk(root, depth: 0) }
        return found
    }

    /// The roots under `home` that exist, from `rootNames`.
    public static func defaultRoots(home: String) -> [String] {
        rootNames.map { (home as NSString).appendingPathComponent($0) }.filter { root in
            var directory: ObjCBool = false
            return FileManager.default.fileExists(atPath: root, isDirectory: &directory) && directory.boolValue
        }
    }

    /// Every linked worktree of the repositories found, listed by `run` (git's arguments and the
    /// folder to run in, returning its output or nil), at most `maximumWorktrees`.
    public static func list(roots: [String], folders: [String], run: (_ arguments: [String], _ directory: String) -> Data?) -> [Worktree] {
        var result: [Worktree] = []
        for repo in repositories(roots: roots, folders: folders) {
            guard let output = run(["worktree", "list", "--porcelain", "-z"], repo) else { continue }
            result += parse(porcelain: output)
            if result.count >= maximumWorktrees { break }
        }
        return Array(result.prefix(maximumWorktrees))
    }

    /// Allocated bytes of the files under `path`, without following symbolic links, stopping at
    /// `deadline` or `maximumFiles`. APFS clones and hard links are
    /// counted in full, so this can exceed what removing the folder frees.
    public static func size(of path: String, deadline: Date, maximumFiles: Int = 2_000_000) -> (bytes: Int64, complete: Bool) {
        let keys: [URLResourceKey] = [.totalFileAllocatedSizeKey, .isRegularFileKey]
        guard let enumerator = FileManager.default.enumerator(at: URL(fileURLWithPath: path, isDirectory: true), includingPropertiesForKeys: keys,
                                                              options: [], errorHandler: { _, _ in true }) else { return (0, false) }
        var total: Int64 = 0, count = 0
        for case let url as URL in enumerator {
            count += 1
            if count % 512 == 0, Date() > deadline || count > maximumFiles { return (total, false) }
            guard let values = try? url.resourceValues(forKeys: Set(keys)), values.isRegularFile == true else { continue }
            total += Int64(values.totalFileAllocatedSize ?? 0)
        }
        return (total, true)
    }
}
#endif
