#if os(macOS)
import XCTest

@testable import VolantCore

final class WorktreeTests: XCTestCase {
    private func worktree(_ path: String, repo: String = "/Users/fictional/workspace/app", branch: String? = "feature", stale: Bool = false) -> Worktree {
        Worktree(repository: repo, path: path, branch: branch, head: "0123456789abcdef", stale: stale)
    }

    private func porcelain(_ records: [[String]]) -> Data {
        Data(records.map { $0.map { $0 + "\0" }.joined() + "\0" }.joined().utf8)
    }

    func testQueryWordsAndStale() {
        XCTAssertEqual(Worktrees.queryTerm("worktrees")?.text, "")
        XCTAssertEqual(Worktrees.queryTerm("WT volant")?.text, "volant")
        XCTAssertEqual(Worktrees.queryTerm("worktree stale")?.staleOnly, true)
        XCTAssertEqual(Worktrees.queryTerm("wt stale cara")?.text, "cara")
        XCTAssertEqual(Worktrees.queryTerm("wt staleness")?.staleOnly, false)
        XCTAssertNil(Worktrees.queryTerm("wtf"))
        XCTAssertNil(Worktrees.queryTerm("worktreeish"))
    }

    func testPorcelainSkipsMainAndBareAndReadsEachKind() {
        let data = porcelain([
            ["worktree /Users/fictional/workspace/app", "HEAD aaaa", "branch refs/heads/main"],
            ["worktree /Users/fictional/workspace/app/.claude/worktrees/one two", "HEAD bbbbbbbbbb", "branch refs/heads/feat/one"],
            ["worktree /Users/fictional/workspace/app/dist-release.ship-1.0.0.x/worktree", "HEAD cccccccccc", "detached", "locked busy"],
            ["worktree /Users/fictional/gone", "HEAD dddd", "branch refs/heads/old", "prunable gitdir file points to non-existent location"],
            ["worktree /Users/fictional/bare.git", "bare"],
        ])
        let items = Worktrees.parse(porcelain: data)
        XCTAssertEqual(items.map(\.path), ["/Users/fictional/workspace/app/.claude/worktrees/one two",
                                           "/Users/fictional/workspace/app/dist-release.ship-1.0.0.x/worktree", "/Users/fictional/gone"])
        XCTAssertEqual(items.map(\.repository), Array(repeating: "/Users/fictional/workspace/app", count: 3))
        XCTAssertEqual(items[0].branch, "feat/one")
        XCTAssertEqual(items[0].title, "one two · feat/one")
        XCTAssertNil(items[1].branch)
        XCTAssertTrue(items[1].locked)
        XCTAssertEqual(items[1].title, "worktree · detached ccccccc")
        XCTAssertTrue(items[2].stale)
        XCTAssertFalse(items[0].stale || items[0].locked)
    }

    func testPorcelainWithoutAMainEntryIsEmpty() {
        XCTAssertEqual(Worktrees.parse(porcelain: Data("fatal: not a git repository".utf8)), [])
        XCTAssertEqual(Worktrees.parse(porcelain: Data()), [])
    }

    func testHolderMatchesWholePathComponents() {
        let item = worktree("/Users/fictional/workspace/app-wt")
        XCTAssertEqual(Worktrees.holder(of: item, among: [("/Users/fictional/workspace/app-wt/web", "Node.js on 3000")]), "Node.js on 3000")
        XCTAssertEqual(Worktrees.holder(of: item, among: [("/Users/fictional/workspace/app-wt", "Rex: app")]), "Rex: app")
        XCTAssertNil(Worktrees.holder(of: item, among: [("/Users/fictional/workspace/app-wt2", "Rex: other")]))
        XCTAssertNil(Worktrees.holder(of: item, among: [("/Users/fictional/workspace", "Rex: parent")]))
    }

    func testArrangeOrdersBySizeAndPutsStaleLast() {
        let items = [worktree("/b", stale: true), worktree("/small"), worktree("/unknown"), worktree("/big")]
        let sizes: [String: Int64] = ["/small": 10, "/big": 1_000]
        XCTAssertEqual(Worktrees.arrange(items, sizes: sizes).map(\.path), ["/big", "/small", "/unknown", "/b"])
        XCTAssertEqual(Worktrees.arrange(items, sizes: sizes, staleOnly: true).map(\.path), ["/b"])
    }

    func testTextMatchesRepositoryBranchAndPath() {
        let items = [worktree("/x/one", repo: "/r/volant", branch: "feat/mcp"), worktree("/x/two", repo: "/r/cara", branch: nil)]
        XCTAssertEqual(Worktrees.arrange(items, matching: "volant").map(\.path), ["/x/one"])
        XCTAssertEqual(Worktrees.arrange(items, matching: "MCP").map(\.path), ["/x/one"])
        XCTAssertEqual(Worktrees.arrange(items, matching: "two").map(\.path), ["/x/two"])
    }

    func testAgeAndPath() {
        let now = Date(timeIntervalSince1970: 10_000_000)
        XCTAssertEqual(Worktrees.age(of: now.addingTimeInterval(-90), now: now), "1m")
        XCTAssertEqual(Worktrees.age(of: now.addingTimeInterval(-86400 * 3), now: now), "3d")
        XCTAssertEqual(Worktrees.age(of: now.addingTimeInterval(-86400 * 21), now: now), "3w")
        XCTAssertEqual(Worktrees.abbreviate("/Users/fictional/workspace/app", home: "/Users/fictional"), "~/workspace/app")
        XCTAssertEqual(Worktrees.abbreviate("/Users/fictionality/app", home: "/Users/fictional"), "/Users/fictionality/app")
    }

    func testDiscoveryFindsRepositoriesWithWorktreesAndSkipsSubmodules() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("worktree-tests-\(UUID().uuidString)").path
        defer { try? FileManager.default.removeItem(atPath: root) }
        let fm = FileManager.default
        func mkdir(_ path: String) throws { try fm.createDirectory(atPath: root + path, withIntermediateDirectories: true) }
        func write(_ path: String, _ text: String) throws { try text.write(toFile: root + path, atomically: true, encoding: .utf8) }
        try mkdir("/workspace/app/.git/worktrees/feature")
        try mkdir("/workspace/app/.claude/worktrees/feature")
        try write("/workspace/app/.claude/worktrees/feature/.git", "gitdir: \(root)/workspace/app/.git/worktrees/feature\n")
        try mkdir("/workspace/plain/.git")
        try mkdir("/workspace/app/vendor/lib")
        try mkdir("/workspace/app/.git/modules/lib")
        try write("/workspace/app/vendor/lib/.git", "gitdir: ../../.git/modules/lib\n")
        try mkdir("/workspace/group/deep/nested/.git/worktrees/x")
        try mkdir("/workspace/node_modules/pkg/.git/worktrees/x")
        try mkdir("/elsewhere/tool/.git/worktrees/y")
        try mkdir("/elsewhere/tool/src")

        let found = Worktrees.repositories(roots: [root + "/workspace"], folders: [root + "/elsewhere/tool/src", root + "/workspace/app/vendor/lib"])
        XCTAssertEqual(Set(found), [root + "/workspace/app", root + "/workspace/group/deep/nested", root + "/elsewhere/tool"])
        XCTAssertEqual(Worktrees.repository(ofWorktree: root + "/workspace/app/.claude/worktrees/feature"), root + "/workspace/app")
        XCTAssertNil(Worktrees.repository(ofWorktree: root + "/workspace/app/vendor/lib"), "A submodule is not a worktree")
        XCTAssertNil(Worktrees.repository(ofWorktree: root + "/workspace/app"))

        var ran: [String] = []
        let items = Worktrees.list(roots: [root + "/workspace"], folders: []) { arguments, directory in
            XCTAssertEqual(arguments, ["worktree", "list", "--porcelain", "-z"])
            ran.append(directory)
            return Data("worktree \(directory)\0HEAD a\0branch refs/heads/main\0\0worktree \(directory)-wt\0HEAD b\0detached\0\0".utf8)
        }
        XCTAssertEqual(Set(ran), [root + "/workspace/app", root + "/workspace/group/deep/nested"])
        XCTAssertEqual(Set(items.map(\.path)), [root + "/workspace/app-wt", root + "/workspace/group/deep/nested-wt"])
    }

    func testSizeCountsFilesAndStopsAtTheDeadline() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("worktree-size-\(UUID().uuidString)").path
        defer { try? FileManager.default.removeItem(atPath: root) }
        try FileManager.default.createDirectory(atPath: root + "/a", withIntermediateDirectories: true)
        try Data(repeating: 1, count: 10_000).write(to: URL(fileURLWithPath: root + "/a/file"))
        let measured = Worktrees.size(of: root, deadline: Date().addingTimeInterval(10))
        XCTAssertTrue(measured.complete)
        XCTAssertGreaterThanOrEqual(measured.bytes, 10_000)
        XCTAssertEqual(Worktrees.formatSize(2_000_000_000, complete: false).last, "+")
    }

    /// Real git output: a repository with one live and one deleted worktree, listed through the
    /// same entry point the helper uses. Skipped where git isn't installed.
    func testRealGitOutputIncludingAPrunableWorktree() throws {
        guard let git = RepositoryStatusCommand.git() else { throw XCTSkip("git is not installed") }
        let base = FileManager.default.temporaryDirectory.appendingPathComponent("worktree-git-\(UUID().uuidString)").path
        try FileManager.default.createDirectory(atPath: base + "/workspace/app", withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(atPath: base) }
        let root = try XCTUnwrap(realpath(base, nil).map { pointer in defer { free(pointer) }; return String(cString: pointer) })
        let repo = root + "/workspace/app"
        func run(_ arguments: [String], in directory: String) -> Data? {
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
        XCTAssertNotNil(run(["init", "-q"], in: repo))
        XCTAssertNotNil(run(["commit", "-q", "--allow-empty", "-m", "first"], in: repo))
        XCTAssertNotNil(run(["worktree", "add", "-q", "-b", "feat/live", repo + "/.claude/worktrees/live with space"], in: repo))
        XCTAssertNotNil(run(["worktree", "add", "-q", "--detach", root + "/gone"], in: repo))
        try FileManager.default.removeItem(atPath: root + "/gone")

        let items = Worktrees.list(roots: [root + "/workspace"], folders: []) { arguments, directory in run(arguments, in: directory) }
            .sorted { $0.stale == $1.stale ? $0.path < $1.path : !$0.stale }
        XCTAssertEqual(items.map(\.path), [repo + "/.claude/worktrees/live with space", root + "/gone"])
        XCTAssertEqual(items.map(\.repository), [repo, repo])
        XCTAssertEqual(items[0].branch, "feat/live")
        XCTAssertFalse(items[0].stale)
        XCTAssertNil(items[1].branch)
        XCTAssertTrue(items[1].stale, "git marks a worktree whose folder is gone as prunable")
        XCTAssertEqual(Worktrees.repository(ofWorktree: items[0].path), repo)
    }
}
#endif
