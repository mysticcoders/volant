#if os(macOS)
import XCTest

@testable import VolantCore

/// Worktree removal against real git in a temporary folder: each refusal leaves the worktree in
/// place, uncommitted work is saved before removal, branches stay, and prune drops only records of
/// missing folders. Skipped where git isn't installed. No folder of the owner's is touched.
final class WorktreeRemoverTests: XCTestCase {
    private var root = ""
    private var git = ""

    override func setUpWithError() throws {
        guard let found = RepositoryStatusCommand.git() else { throw XCTSkip("git is not installed") }
        git = found
        let base = FileManager.default.temporaryDirectory.appendingPathComponent("worktree-remover-\(UUID().uuidString)").path
        try FileManager.default.createDirectory(atPath: base + "/repo", withIntermediateDirectories: true)
        root = try XCTUnwrap(realpath(base, nil).map { pointer in defer { free(pointer) }; return String(cString: pointer) })
        XCTAssertNotNil(run(["init", "-q"], in: repo))
        try "one\n".write(toFile: repo + "/file.txt", atomically: true, encoding: .utf8)
        XCTAssertNotNil(run(["add", "file.txt"], in: repo))
        XCTAssertNotNil(run(["commit", "-q", "-m", "first"], in: repo))
    }

    override func tearDownWithError() throws { try? FileManager.default.removeItem(atPath: root) }

    private var repo: String { root + "/repo" }

    @discardableResult
    private func run(_ arguments: [String], in directory: String, timeout: TimeInterval = 30) -> Data? {
        let task = Process(), output = Pipe()
        task.executableURL = URL(fileURLWithPath: git)
        task.arguments = ["-c", "user.name=Fictional", "-c", "user.email=fictional@example.com", "-c", "init.defaultBranch=main"] + arguments
        task.currentDirectoryURL = URL(fileURLWithPath: directory)
        task.environment = RepositoryStatusCommand.environment(home: root)
        task.standardOutput = output; task.standardError = Pipe()
        guard (try? task.run()) != nil else { return nil }
        let data = output.fileHandleForReading.readDataToEndOfFile()
        task.waitUntilExit()
        return task.terminationStatus == 0 ? data : nil
    }

    private func remover(processes: [String] = []) -> WorktreeRemover {
        WorktreeRemover(git: { [unowned self] arguments, directory, timeout in self.run(arguments, in: directory, timeout: timeout) },
                        backupRoot: root + "/backups", processesInside: { _ in processes },
                        now: { Date(timeIntervalSince1970: 1_795_060_000) })
    }

    private func add(_ name: String, branch: String? = nil) throws -> Worktree {
        let path = root + "/" + name
        XCTAssertNotNil(run(["worktree", "add", "-q"] + (branch.map { ["-b", $0] } ?? ["--detach"]) + [path], in: repo))
        return try XCTUnwrap(Worktrees.parse(porcelain: try XCTUnwrap(run(["worktree", "list", "--porcelain", "-z"], in: repo))).first { $0.path == path })
    }

    private func request(_ item: Worktree, head: String? = nil) -> WorktreeRemovalRequest {
        WorktreeRemovalRequest(repository: item.repository, path: item.path, head: head ?? item.head ?? "")
    }

    private func refusal(_ body: () throws -> Any) -> HostMessage.Code? {
        do { _ = try body(); return nil } catch let message as HostMessage { return message.code } catch { return nil }
    }

    func testCleanWorktreeIsRemovedAndItsBranchKept() throws {
        let item = try add("clean", branch: "feat/clean")
        let result = try remover().remove(request(item))
        XCTAssertNil(result.backup, "Nothing uncommitted, nothing saved")
        XCTAssertFalse(FileManager.default.fileExists(atPath: item.path))
        XCTAssertNotNil(run(["rev-parse", "--verify", "-q", "refs/heads/feat/clean"], in: repo), "The branch stays")
        XCTAssertTrue(FileManager.default.fileExists(atPath: repo + "/file.txt"), "The main working folder is untouched")
    }

    func testUncommittedWorkIsSavedBeforeRemoval() throws {
        let item = try add("dirty", branch: "feat/dirty")
        try "changed\n".write(toFile: item.path + "/file.txt", atomically: true, encoding: .utf8)
        try FileManager.default.createDirectory(atPath: item.path + "/notes", withIntermediateDirectories: true)
        try "draft\n".write(toFile: item.path + "/notes/new file.md", atomically: true, encoding: .utf8)
        try "ignored\n".write(toFile: item.path + "/.gitignore", atomically: true, encoding: .utf8)
        try "skip me\n".write(toFile: item.path + "/ignored", atomically: true, encoding: .utf8)

        let result = try remover().remove(request(item))
        let backup = try XCTUnwrap(result.backup)
        let day = DateFormatter()
        day.locale = Locale(identifier: "en_US_POSIX"); day.dateFormat = "yyyy-MM-dd"
        let dated = root + "/backups/" + day.string(from: Date(timeIntervalSince1970: 1_795_060_000))
        XCTAssertEqual(backup, dated + "/repo-dirty")
        let patch = try String(contentsOfFile: backup + "/changes.patch", encoding: .utf8)
        XCTAssertTrue(patch.contains("+changed"), patch)
        XCTAssertEqual(try String(contentsOfFile: backup + "/untracked/notes/new file.md", encoding: .utf8), "draft\n")
        XCTAssertTrue(FileManager.default.fileExists(atPath: backup + "/untracked/.gitignore"))
        XCTAssertFalse(FileManager.default.fileExists(atPath: backup + "/untracked/ignored"), "Ignored files are not saved")
        XCTAssertTrue(try String(contentsOfFile: backup + "/README.txt", encoding: .utf8).contains("branch feat/dirty"))
        XCTAssertFalse(FileManager.default.fileExists(atPath: item.path))

        let again = try add("dirty", branch: "feat/dirty-2")
        try "more\n".write(toFile: again.path + "/extra.txt", atomically: true, encoding: .utf8)
        XCTAssertEqual(try remover().remove(request(again)).backup, dated + "/repo-dirty-2", "A second backup gets its own folder")
    }

    func testRefusalsLeaveTheWorktreeInPlace() throws {
        let item = try add("guarded", branch: "feat/guarded")
        XCTAssertEqual(refusal { try self.remover(processes: ["zsh"]).remove(self.request(item)) }, .worktreeInUse)
        XCTAssertEqual(refusal { try self.remover().remove(self.request(item, head: String(repeating: "a", count: 40))) }, .worktreeChanged)
        XCTAssertEqual(refusal { try self.remover().remove(WorktreeRemovalRequest(repository: self.repo, path: self.repo, head: item.head ?? "")) }, .worktreeChanged,
                       "The main working folder is never removed")
        XCTAssertEqual(refusal { try self.remover().remove(self.request(item, head: "not-a-commit")) }, .worktreeChanged)
        run(["worktree", "lock", item.path], in: repo)
        XCTAssertEqual(refusal { try self.remover().remove(self.request(item)) }, .worktreeLocked)
        XCTAssertTrue(FileManager.default.fileExists(atPath: item.path + "/file.txt"))
    }

    func testCommitsNoBranchHoldsAreNotLost() throws {
        let item = try add("detached")
        try "work\n".write(toFile: item.path + "/file.txt", atomically: true, encoding: .utf8)
        run(["commit", "-q", "-am", "detached work"], in: item.path)
        let moved = try XCTUnwrap(Worktrees.parse(porcelain: try XCTUnwrap(run(["worktree", "list", "--porcelain", "-z"], in: repo))).first { $0.path == item.path })
        XCTAssertEqual(refusal { try self.remover().remove(self.request(moved)) }, .worktreeUnreachable)
        XCTAssertTrue(FileManager.default.fileExists(atPath: item.path))
        run(["branch", "keep", "HEAD"], in: item.path)
        XCTAssertNoThrow(try remover().remove(request(moved)), "Once a branch holds the commit, it can go")
    }

    func testPruneDropsOnlyMissingFolders() throws {
        let live = try add("live", branch: "feat/live")
        let gone = try add("gone", branch: "feat/gone")
        try FileManager.default.removeItem(atPath: gone.path)
        XCTAssertEqual(try remover().prune(repository: repo), 1)
        let left = Worktrees.parse(porcelain: try XCTUnwrap(run(["worktree", "list", "--porcelain", "-z"], in: repo)))
        XCTAssertEqual(left.map(\.path), [live.path])
        XCTAssertEqual(refusal { try self.remover().prune(repository: live.path) }, .worktreeChanged, "Prune runs only in a main repository")
    }

    func testProcessesInsideAFolderAreFound() throws {
        let folder = root + "/busy"
        try FileManager.default.createDirectory(atPath: folder + "/sub", withIntermediateDirectories: true)
        let sleeper = Process()
        sleeper.executableURL = URL(fileURLWithPath: "/bin/sleep")
        sleeper.arguments = ["30"]
        sleeper.currentDirectoryURL = URL(fileURLWithPath: folder + "/sub")
        try sleeper.run()
        defer { sleeper.terminate() }
        Thread.sleep(forTimeInterval: 0.2)
        XCTAssertTrue(ListeningServers.processes(workingInside: folder).contains("sleep"))
        XCTAssertFalse(ListeningServers.processes(workingInside: folder + "-other").contains("sleep"))
    }
}
#endif
