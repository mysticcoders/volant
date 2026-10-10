import Foundation
import XCTest

@testable import VolantCore

/// Isolated workspaces against a real git in throwaway folders. The fixture repositories, hooks
/// and filters are fictional; HOME points at an empty folder, so the owner's git settings are never
/// read.
final class ACPWorktreeTests: XCTestCase {
    private var scratch: URL!
    private var home: URL!
    private var root: URL!
    private var executable: String!

    override func setUpWithError() throws {
        // The installer stub at /usr/bin/git is acceptable here: a test machine has developer tools.
        let candidates = ["/opt/homebrew/bin/git", "/usr/local/bin/git", "/Library/Developer/CommandLineTools/usr/bin/git",
                          "/Applications/Xcode.app/Contents/Developer/usr/bin/git", "/usr/bin/git"]
        guard let found = candidates.first(where: { FileManager.default.isExecutableFile(atPath: $0) }) else {
            throw XCTSkip("No git on this machine")
        }
        executable = found
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("volant-worktree-" + UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        scratch = folder.resolvingSymlinksInPath()
        home = scratch.appendingPathComponent("home", isDirectory: true)
        root = scratch.appendingPathComponent("Worktrees", isDirectory: true)
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let scratch { try? FileManager.default.removeItem(at: scratch) }
    }

    /// The runner the helper would use, built on Foundation's Process.
    private var runner: ACPWorktree.Run {
        let git = executable!
        return { arguments, directory, environment in
            let process = Process(), output = Pipe()
            process.executableURL = URL(fileURLWithPath: git)
            process.arguments = arguments
            process.currentDirectoryURL = URL(fileURLWithPath: directory)
            process.environment = environment
            process.standardOutput = output
            process.standardError = FileHandle.nullDevice
            try process.run()
            let data = output.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            return GitResult(status: process.terminationStatus, output: data)
        }
    }

    private var worktrees: ACPWorktree { ACPWorktree(root: root, home: home.path, run: runner) }

    /// Fixture setup, with a fictional identity and no system configuration.
    @discardableResult
    private func git(_ arguments: [String], in directory: URL) throws -> String {
        let environment = RepositoryStatusCommand.environment(home: home.path).merging([
            "GIT_CONFIG_NOSYSTEM": "1", "GIT_AUTHOR_NAME": "Fixture", "GIT_AUTHOR_EMAIL": "fixture@example.com",
            "GIT_COMMITTER_NAME": "Fixture", "GIT_COMMITTER_EMAIL": "fixture@example.com"]) { $1 }
        let result = try runner(arguments, directory.path, environment)
        XCTAssertEqual(result.status, 0, "git " + arguments.joined(separator: " "))
        return String(decoding: result.output, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// A repository on branch `fixture` with one commit.
    private func repository(_ name: String = "orbit-web") throws -> URL {
        let url = scratch.appendingPathComponent(name, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        try git(["init", "-q", "-b", "fixture"], in: url)
        try Data("first\n".utf8).write(to: url.appendingPathComponent("README.md"))
        try git(["add", "README.md"], in: url)
        try git(["commit", "-q", "-m", "First"], in: url)
        return url
    }

    private func state(of path: String) throws -> RepositoryState? {
        RepositoryState.parse(porcelainV2: try git(RepositoryStatusCommand.arguments, in: URL(fileURLWithPath: path)) + "\n")
    }

    private func branchExists(_ branch: String, in repository: URL) -> Bool {
        let result = try? runner(["rev-parse", "--verify", "--quiet", "refs/heads/" + branch], repository.path,
                                 RepositoryStatusCommand.environment(home: home.path))
        return result?.status == 0
    }

    func testCreatesAWorkspaceOnItsOwnBranchTrackingTheSourceBranch() throws {
        let source = try repository()
        let path = try worktrees.create(project: source.path, id: "ab12cd34")
        XCTAssertEqual(path, root.appendingPathComponent("orbit-web-ab12cd34").resolvingSymlinksInPath().path)
        XCTAssertEqual(try state(of: path), RepositoryState(branch: "volant/ab12cd34"))
        XCTAssertEqual(try git(["config", "branch.volant/ab12cd34.merge"], in: source), "refs/heads/fixture")
        XCTAssertEqual(try git(["config", "branch.volant/ab12cd34.remote"], in: source), ".")
        XCTAssertEqual(try state(of: source.path)?.branch, "fixture", "the owner's checkout keeps its branch")

        try Data("agent\n".utf8).write(to: URL(fileURLWithPath: path).appendingPathComponent("agent.txt"))
        XCTAssertEqual(try state(of: path)?.summary, "volant/ab12cd34 · 1 changed")
        try git(["add", "agent.txt"], in: URL(fileURLWithPath: path))
        try git(["commit", "-q", "-m", "Agent work"], in: URL(fileURLWithPath: path))
        XCTAssertEqual(try state(of: path)?.summary, "volant/ab12cd34 · 1 ahead", "commits count against the source branch")
        XCTAssertFalse(FileManager.default.fileExists(atPath: source.appendingPathComponent("agent.txt").path))
    }

    func testRepositoryHooksDoNotRun() throws {
        let source = try repository()
        let marker = scratch.appendingPathComponent("hook-ran")
        try FileManager.default.createDirectory(at: source.appendingPathComponent(".git/hooks"), withIntermediateDirectories: true)
        let hook = source.appendingPathComponent(".git/hooks/post-checkout")
        try Data("#!/bin/sh\ntouch '\(marker.path)'\n".utf8).write(to: hook)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: hook.path)
        _ = try worktrees.create(project: source.path, id: "0000aaaa")
        XCTAssertFalse(FileManager.default.fileExists(atPath: marker.path), "post-checkout must not run")
    }

    func testAFilterAHookOrAConditionalIncludeInTheRepositorysOwnSettingsIsRefused() throws {
        let source = try repository()
        try git(["config", "filter.fixture.smudge", "cat"], in: source)
        XCTAssertThrowsError(try worktrees.create(project: source.path, id: "0000bbbb")) { error in
            XCTAssertTrue(error.localizedDescription.contains("define a filter, a hook or a conditional include"), error.localizedDescription)
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent("orbit-web-0000bbbb").path))
        XCTAssertFalse(branchExists("volant/0000bbbb", in: source), "nothing is created")

        let included = try repository("included-filter")
        let extra = scratch.appendingPathComponent("extra.gitconfig")
        try Data("[filter \"fixture\"]\n\tsmudge = cat\n".utf8).write(to: extra)
        try git(["config", "include.path", extra.path], in: included)
        XCTAssertThrowsError(try worktrees.create(project: included.path, id: "0000cccc"), "an included file counts as the repository's own")

        // Without the refusal each of these would run the fixture command: a filter included only on
        // the new branch or for the new worktree's git folder, or a hook that core.hooksPath doesn't
        // govern (git 2.54 and later).
        let marker = scratch.appendingPathComponent("setting-ran")
        let conditional = scratch.appendingPathComponent("conditional.gitconfig")
        try Data("[filter \"fixture\"]\n\tsmudge = \"touch '\(marker.path)'; cat\"\n".utf8).write(to: conditional)
        let settings = [["includeIf.onbranch:volant/**.path", conditional.path],
                        ["includeIf.gitdir:**/.git/worktrees/**.path", conditional.path],
                        ["hook.fixture.command", "touch '\(marker.path)'"]]
        for (index, setting) in settings.enumerated() {
            let fixture = try repository("setting-\(index)")
            try Data("*.txt filter=fixture\n".utf8).write(to: fixture.appendingPathComponent(".gitattributes"))
            try Data("text\n".utf8).write(to: fixture.appendingPathComponent("notes.txt"))
            try git(["add", ".gitattributes", "notes.txt"], in: fixture)
            try git(["commit", "-q", "-m", "Filtered"], in: fixture)
            try git(["config"] + setting, in: fixture)
            if setting[0].hasPrefix("hook.") { try git(["config", "hook.fixture.event", "post-checkout"], in: fixture) }
            XCTAssertThrowsError(try worktrees.create(project: fixture.path, id: "0000c00\(index)"), setting[0])
            XCTAssertFalse(FileManager.default.fileExists(atPath: marker.path), setting[0] + " must not run")
        }
    }

    func testSettingsAreReadBeforeAnyStatusRunsAFilter() throws {
        let source = try repository()
        try Data("*.txt filter=fixture\n".utf8).write(to: source.appendingPathComponent(".gitattributes"))
        let notes = source.appendingPathComponent("notes.txt")
        try Data("text\n".utf8).write(to: notes)
        try git(["add", ".gitattributes", "notes.txt"], in: source)
        try git(["commit", "-q", "-m", "Filtered"], in: source)
        let path = try worktrees.create(project: source.path, id: "0000c100")
        // Only now is the filter defined. A new timestamp makes status pass the file through it.
        let marker = scratch.appendingPathComponent("clean-ran")
        try git(["config", "filter.fixture.clean", "touch '\(marker.path)'; cat"], in: source)
        let later = Date().addingTimeInterval(120)
        try FileManager.default.setAttributes([.modificationDate: later], ofItemAtPath: notes.path)
        XCTAssertThrowsError(try worktrees.create(project: source.path, id: "0000c101"))
        try FileManager.default.setAttributes([.modificationDate: later], ofItemAtPath: path + "/notes.txt")
        XCTAssertThrowsError(try worktrees.remove(path: path)) { error in
            XCTAssertTrue(error.localizedDescription.contains("git worktree remove"), error.localizedDescription)
        }
        XCTAssertTrue(FileManager.default.fileExists(atPath: path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: marker.path), "the clean command must not run")
    }

    func testAGlobalFilterDoesNotRunAndTheFileStaysAsCommitted() throws {
        let source = try repository()
        try Data("*.bin filter=fixture\n".utf8).write(to: source.appendingPathComponent(".gitattributes"))
        try Data("version fictional-pointer\n".utf8).write(to: source.appendingPathComponent("asset.bin"))
        try git(["add", ".gitattributes", "asset.bin"], in: source)
        try git(["commit", "-q", "-m", "Asset"], in: source)
        // Only now does the fictional owner have a filter, in both global locations git reads.
        let marker = scratch.appendingPathComponent("filter-ran")
        let filter = "[filter \"fixture\"]\n\tsmudge = \"touch '\(marker.path)' && sed s/pointer/smudged/\"\n"
        try Data(filter.utf8).write(to: home.appendingPathComponent(".gitconfig"))
        try FileManager.default.createDirectory(at: home.appendingPathComponent(".config/git"), withIntermediateDirectories: true)
        try Data(filter.utf8).write(to: home.appendingPathComponent(".config/git/config"))

        let path = try worktrees.create(project: source.path, id: "0000dddd")
        XCTAssertEqual(try String(contentsOf: URL(fileURLWithPath: path).appendingPathComponent("asset.bin"), encoding: .utf8),
                       "version fictional-pointer\n", "the file stays as committed, as a Git LFS pointer would")
        XCTAssertFalse(FileManager.default.fileExists(atPath: marker.path), "the global filter must not run")
    }

    func testADetachedHeadStartsAtItsCommitWithoutUpstream() throws {
        let source = try repository()
        try git(["checkout", "-q", "--detach"], in: source)
        let path = try worktrees.create(project: source.path, id: "0000eeee")
        XCTAssertEqual(try state(of: path), RepositoryState(branch: "volant/0000eeee"))
        XCTAssertEqual(try git(["rev-parse", "HEAD"], in: URL(fileURLWithPath: path)), try git(["rev-parse", "HEAD"], in: source))
        let upstream = try runner(["config", "branch.volant/0000eeee.merge"], source.path, RepositoryStatusCommand.environment(home: home.path))
        XCTAssertEqual(upstream.status, 1, "no upstream, so no ahead or behind")
    }

    func testRefusesAFolderThatIsNotARepositoryAnExistingPathAndABadID() throws {
        let plain = scratch.appendingPathComponent("plain", isDirectory: true)
        try FileManager.default.createDirectory(at: plain, withIntermediateDirectories: true)
        XCTAssertThrowsError(try worktrees.create(project: plain.path, id: "0000ffff")) { error in
            XCTAssertTrue(error.localizedDescription.contains("isn’t a Git repository"), error.localizedDescription)
        }
        XCTAssertThrowsError(try worktrees.create(project: "", id: "0000ffff"), "general chat has no repository")
        XCTAssertThrowsError(try worktrees.create(project: "relative/orbit", id: "0000ffff"))
        let source = try repository()
        let taken = root.appendingPathComponent("orbit-web-11112222", isDirectory: true)
        try FileManager.default.createDirectory(at: taken, withIntermediateDirectories: true)
        XCTAssertThrowsError(try worktrees.create(project: source.path, id: "11112222")) { error in
            XCTAssertTrue(error.localizedDescription.contains("already exists"), error.localizedDescription)
        }
        XCTAssertFalse(branchExists("volant/11112222", in: source))
        let dangling = root.appendingPathComponent("orbit-web-11113333")
        try FileManager.default.createSymbolicLink(at: dangling, withDestinationURL: scratch.appendingPathComponent("missing"))
        XCTAssertThrowsError(try worktrees.create(project: source.path, id: "11113333")) { error in
            XCTAssertTrue(error.localizedDescription.contains("already exists"), "a dangling link counts: " + error.localizedDescription)
        }
        XCTAssertFalse(branchExists("volant/11113333", in: source))
        try git(["branch", "volant/11114444"], in: source)
        XCTAssertThrowsError(try worktrees.create(project: source.path, id: "11114444")) { error in
            XCTAssertTrue(error.localizedDescription.contains("already has a branch"), error.localizedDescription)
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent("orbit-web-11114444").path))
        for bad in ["ABCDEF12", "abc", "abcdefgh", "../../x1", "0000ffff0"] {
            XCTAssertThrowsError(try worktrees.create(project: source.path, id: bad), bad)
        }
    }

    func testRemovalRefusesChangesAndKeepsTheBranchOfACleanWorkspace() throws {
        let source = try repository()
        let path = try worktrees.create(project: source.path, id: "33334444")
        let workspace = URL(fileURLWithPath: path)
        try Data("edited\n".utf8).write(to: workspace.appendingPathComponent("README.md"))
        XCTAssertThrowsError(try worktrees.remove(path: path)) { error in
            XCTAssertTrue(error.localizedDescription.contains("uncommitted or untracked"), error.localizedDescription)
        }
        try git(["checkout", "-q", "--", "README.md"], in: workspace)
        try Data("new\n".utf8).write(to: workspace.appendingPathComponent("untracked.txt"))
        XCTAssertThrowsError(try worktrees.remove(path: path), "an untracked file is a change")
        try git(["add", "untracked.txt"], in: workspace)
        try git(["commit", "-q", "-m", "Keep this"], in: workspace)
        try git(["checkout", "-q", "--detach"], in: workspace)
        XCTAssertThrowsError(try worktrees.remove(path: path), "a detached workspace could hold commits on no branch")
        try git(["checkout", "-q", "volant/33334444"], in: workspace)
        try FileManager.default.createDirectory(at: source.appendingPathComponent(".git/info"), withIntermediateDirectories: true)
        try Data("build/\n".utf8).write(to: source.appendingPathComponent(".git/info/exclude"))
        try FileManager.default.createDirectory(at: workspace.appendingPathComponent("build"), withIntermediateDirectories: true)
        try Data("output\n".utf8).write(to: workspace.appendingPathComponent("build/out.o"))

        XCTAssertEqual(try worktrees.remove(path: path), "volant/33334444")
        XCTAssertFalse(FileManager.default.fileExists(atPath: path), "ignored files go with the workspace")
        XCTAssertTrue(branchExists("volant/33334444", in: source), "the branch and its commit stay")
        XCTAssertEqual(try git(["log", "-1", "--format=%s", "volant/33334444"], in: source), "Keep this")
        XCTAssertNil(try worktrees.remove(path: path), "a workspace that is gone has nothing to remove")
    }

    func testRemovalIgnoresWhatTheOwnersGlobalExcludesFileIgnores() throws {
        let source = try repository()
        let path = try worktrees.create(project: source.path, id: "33335555")
        try Data("[core]\n\texcludesFile = ~/.gitignore_fixture\n".utf8).write(to: home.appendingPathComponent(".gitconfig"))
        try Data(".DS_Store\n".utf8).write(to: home.appendingPathComponent(".gitignore_fixture"))
        try Data().write(to: URL(fileURLWithPath: path).appendingPathComponent(".DS_Store"))
        XCTAssertEqual(try worktrees.remove(path: path), "volant/33335555")
        XCTAssertFalse(FileManager.default.fileExists(atPath: path))
    }

    func testAWorkspaceOfALinkedWorktreeOfABareRepositoryIsRemoved() throws {
        let seed = try repository("seed")
        let bare = scratch.appendingPathComponent("orbit.git", isDirectory: true)
        try git(["init", "-q", "--bare", bare.path], in: scratch)
        try git(["push", "-q", bare.path, "fixture"], in: seed)
        let checkout = scratch.appendingPathComponent("orbit", isDirectory: true)
        try git(["worktree", "add", "-q", checkout.path, "fixture"], in: bare)
        let path = try worktrees.create(project: checkout.path, id: "55556666")
        XCTAssertEqual(try worktrees.remove(path: path), "volant/55556666")
        XCTAssertFalse(FileManager.default.fileExists(atPath: path))
        XCTAssertTrue(branchExists("volant/55556666", in: bare))
    }

    func testCreationsOnOneRepositoryAtOnceAllSucceed() throws {
        let source = try repository()
        let worktrees = self.worktrees, lock = NSLock()
        var made: [String] = []
        for round in 0..<3 {
            DispatchQueue.concurrentPerform(iterations: 4) { index in
                if let path = try? worktrees.create(project: source.path, id: "a000000" + String(round * 4 + index, radix: 16)) {
                    lock.lock(); made.append(path); lock.unlock()
                }
            }
        }
        XCTAssertEqual(made.count, 12, "two runs of worktree add --track race for the configuration lock")
        for index in 0..<12 {
            XCTAssertEqual(try git(["config", "branch.volant/a000000" + String(index, radix: 16) + ".merge"], in: source), "refs/heads/fixture")
        }
    }

    func testAWorkspaceGitMadeIsKeptWhenItsOutputIsLost() throws {
        let source = try repository()
        let real = runner
        let lossy = ACPWorktree(root: root, home: home.path) { arguments, directory, environment in
            let result = try real(arguments, directory, environment)
            if arguments.contains("worktree") { throw NSError(domain: "VolantWorktreeTests", code: 1) }
            return result
        }
        let path = try lossy.create(project: source.path, id: "77778888")
        XCTAssertEqual(try state(of: path), RepositoryState(branch: "volant/77778888"))
    }

    func testAFailedCreationDeletesTheBranchItMadeAndNamesWhatRemains() throws {
        let source = try repository()
        // A file where git keeps its worktree records fails `worktree add` after it made the branch.
        try Data().write(to: source.appendingPathComponent(".git/worktrees"))
        XCTAssertThrowsError(try worktrees.create(project: source.path, id: "99990000")) { error in
            XCTAssertTrue(error.localizedDescription.contains("at least one commit"), error.localizedDescription)
        }
        XCTAssertFalse(branchExists("volant/99990000", in: source), "the branch the failed run made is deleted")
        let tracking = try runner(["config", "--get-regexp", "^branch\\.volant/"], source.path, RepositoryStatusCommand.environment(home: home.path))
        XCTAssertEqual(tracking.status, 1, "and its tracking settings with it")

        let real = runner
        let keepsBranch = ACPWorktree(root: root, home: home.path) { arguments, directory, environment in
            if arguments.contains("-d") { return GitResult(status: 1, output: Data()) }
            return try real(arguments, directory, environment)
        }
        XCTAssertThrowsError(try keepsBranch.create(project: source.path, id: "99990001")) { error in
            XCTAssertTrue(error.localizedDescription.hasSuffix("left the branch volant/99990001."), error.localizedDescription)
        }
        let partial = root.appendingPathComponent("orbit-web-99990002").path
        let stopped = ACPWorktree(root: root, home: home.path) { arguments, directory, environment in
            guard arguments.contains("worktree") else { return try real(arguments, directory, environment) }
            try FileManager.default.createDirectory(atPath: partial, withIntermediateDirectories: true)
            return GitResult(status: 143, output: Data())
        }
        XCTAssertThrowsError(try stopped.create(project: source.path, id: "99990002")) { error in
            XCTAssertTrue(error.localizedDescription.contains("left the folder " + partial), error.localizedDescription)
        }
        XCTAssertTrue(FileManager.default.fileExists(atPath: partial), "Volant doesn't delete a folder it didn't finish")

        let empty = scratch.appendingPathComponent("empty", isDirectory: true)
        try FileManager.default.createDirectory(at: empty, withIntermediateDirectories: true)
        try git(["init", "-q", "-b", "fixture"], in: empty)
        XCTAssertThrowsError(try worktrees.create(project: empty.path, id: "99990003")) { error in
            XCTAssertTrue(error.localizedDescription.contains("at least one commit"), error.localizedDescription)
        }
        XCTAssertFalse(branchExists("volant/99990003", in: empty))
    }

    func testRemovalRefusesPathsOutsideTheRoot() throws {
        let source = try repository()
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        XCTAssertThrowsError(try worktrees.remove(path: source.path), "the owner's own checkout")
        XCTAssertThrowsError(try worktrees.remove(path: root.path + "/../orbit-web"), "a relative step out of the root")
        XCTAssertThrowsError(try worktrees.remove(path: root.path), "the root itself")
        XCTAssertTrue(FileManager.default.fileExists(atPath: source.appendingPathComponent("README.md").path))
    }

    func testInsideResolvesRelativeStepsAndSymlinks() throws {
        try FileManager.default.createDirectory(at: root.appendingPathComponent("orbit-web-ab12cd34"), withIntermediateDirectories: true)
        let outside = scratch.appendingPathComponent("outside", isDirectory: true)
        try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: root.appendingPathComponent("escape"), withDestinationURL: outside)
        XCTAssertTrue(ACPWorktree.isInside(root.path + "/orbit-web-ab12cd34", root: root))
        XCTAssertFalse(ACPWorktree.isInside(root.path + "/orbit-web-ab12cd34/../../outside", root: root))
        XCTAssertFalse(ACPWorktree.isInside(root.path + "/escape", root: root), "a link inside the root that points outside it")
        XCTAssertFalse(ACPWorktree.isInside(root.path, root: root))
        XCTAssertFalse(ACPWorktree.isInside(root.path + "-other/orbit", root: root), "a sibling sharing the root's name as a prefix")
        XCTAssertFalse(ACPWorktree.isInside("orbit-web-ab12cd34", root: root))
        XCTAssertFalse(ACPWorktree.isInside(root.path + "/orbit\0", root: root))
    }
}

/// The rules that need no git: every call is guarded, and invalid input runs nothing.
final class ACPWorktreeCommandTests: XCTestCase {
    func testEveryCallIgnoresSystemAndGlobalSettingsHooksAndFsmonitor() throws {
        var calls: [(arguments: [String], environment: [String: String])] = []
        let project = FileManager.default.temporaryDirectory.resolvingSymlinksInPath()
        let root = project.appendingPathComponent("volant-worktree-" + UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let worktrees = ACPWorktree(root: root, home: "/fictional-home") { arguments, _, environment in
            calls.append((arguments, environment))
            // A status on branch "main"; no refused setting, no such branch, and a worktree add that fails.
            if arguments.contains("status") { return GitResult(status: 0, output: Data("# branch.oid abc\n# branch.head main\n".utf8)) }
            return GitResult(status: 1, output: Data())
        }
        XCTAssertThrowsError(try worktrees.create(project: project.path, id: "ab12cd34"))
        let commands = calls.map { Array($0.arguments.dropFirst(4)) }
        XCTAssertEqual(commands.first, ["config", "--includes", "--name-only", "--get-regexp", "^(filter|hook|includeif)\\."],
                       "settings are read before any status")
        let path = root.appendingPathComponent(project.lastPathComponent + "-ab12cd34").path
        XCTAssertTrue(commands.contains(["worktree", "add", "--quiet", "--track", "-b", "volant/ab12cd34", path, "refs/heads/main"]))
        XCTAssertEqual(calls.count, 5, "settings, status, the branch, worktree add, and the branch again")
        for call in calls {
            XCTAssertEqual(Array(call.arguments.prefix(4)), ["-c", "core.fsmonitor=false", "-c", "core.hooksPath=/dev/null"])
            XCTAssertEqual(call.environment["GIT_CONFIG_NOSYSTEM"], "1")
            XCTAssertEqual(call.environment["GIT_CONFIG_GLOBAL"], "/dev/null")
            XCTAssertEqual(call.environment["HOME"], "/fictional-home")
            XCTAssertFalse(call.arguments.contains("--force"))
        }
    }

    func testRemovalReadsOnlyTheOwnersExcludesFileFromTheGlobalSettings() throws {
        var calls: [(arguments: [String], directory: String, environment: [String: String])] = []
        let root = FileManager.default.temporaryDirectory.resolvingSymlinksInPath().appendingPathComponent("volant-worktree-" + UUID().uuidString)
        let workspace = root.appendingPathComponent("orbit-web-ab12cd34").path
        try FileManager.default.createDirectory(atPath: workspace, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let worktrees = ACPWorktree(root: root, home: "/fictional-home") { arguments, directory, environment in
            calls.append((arguments, directory, environment))
            let output: String
            if arguments.contains("--get-regexp") { return GitResult(status: 1, output: Data()) }
            else if arguments.contains("--global") { output = "/fictional-home/.gitignore_fixture\n" }
            else if arguments.contains("status") { output = "# branch.oid abc\n# branch.head volant/ab12cd34\n" }
            else if arguments.contains("rev-parse") { output = "/fictional/orbit-web/.git\n" }
            else { output = "" }
            return GitResult(status: 0, output: Data(output.utf8))
        }
        XCTAssertEqual(try worktrees.remove(path: workspace), "volant/ab12cd34")
        XCTAssertEqual(calls.count, 5)
        let excludes = ["-c", "core.excludesFile=/fictional-home/.gitignore_fixture"]
        for call in calls {
            XCTAssertEqual(Array(call.arguments.prefix(4)), ["-c", "core.fsmonitor=false", "-c", "core.hooksPath=/dev/null"])
            XCTAssertEqual(call.environment["GIT_CONFIG_GLOBAL"], call.arguments.contains("--global") ? nil : "/dev/null")
            XCTAssertEqual(call.environment["GIT_CONFIG_NOSYSTEM"], "1")
            XCTAssertFalse(call.arguments.contains("--force"))
            if call.arguments.contains("status") || call.arguments.contains("remove") {
                XCTAssertEqual(Array(call.arguments[4..<6]), excludes)
            }
        }
        XCTAssertEqual(calls.last.map { Array($0.arguments.suffix(3)) }, ["worktree", "remove", workspace])
        XCTAssertEqual(calls.last?.directory, "/fictional/orbit-web/.git", "run from the repository's git folder")
    }

    func testInvalidInputRunsNoGit() {
        var calls = 0
        let worktrees = ACPWorktree(root: URL(fileURLWithPath: "/nonexistent-volant-root"), home: "/fictional-home") { _, _, _ in
            calls += 1
            return GitResult(status: 0, output: Data())
        }
        XCTAssertThrowsError(try worktrees.create(project: "/", id: "not-hex!"))
        XCTAssertThrowsError(try worktrees.create(project: "/nonexistent-fictional-project", id: "ab12cd34"))
        XCTAssertThrowsError(try worktrees.remove(path: "/etc"))
        XCTAssertThrowsError(try worktrees.remove(path: "/nonexistent-volant-root/../etc"))
        XCTAssertEqual(calls, 0)
    }

    func testIDsAndFolderNames() {
        for _ in 0..<50 { XCTAssertTrue(ACPWorktree.isValidID(ACPWorktree.newID())) }
        XCTAssertEqual(ACPWorktree.folderName(project: "/Users/fictional/orbit-web", id: "ab12cd34"), "orbit-web-ab12cd34")
        XCTAssertEqual(ACPWorktree.folderName(project: "/Users/fictional/My Project (2)", id: "ab12cd34"), "My-Project--2--ab12cd34")
        XCTAssertEqual(ACPWorktree.folderName(project: "/Users/fictional/\u{00DC}ber", id: "ab12cd34"), "U-ber-ab12cd34")
        XCTAssertEqual(ACPWorktree.folderName(project: "/Users/fictional/U\u{0308}ber", id: "ab12cd34"), "U-ber-ab12cd34")
        XCTAssertEqual(ACPWorktree.folderName(project: "/Users/fictional/" + String(repeating: "a", count: 100), id: "ab12cd34"),
                       String(repeating: "a", count: 64) + "-ab12cd34")
    }
}
