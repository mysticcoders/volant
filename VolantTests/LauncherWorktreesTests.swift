import CryptoKit
import VolantCore
import XCTest
@testable import Volant

/// The Worktrees command against a scripted helper: In Use from a listening server's folder, the
/// rest largest first, stale entries last, sizes and change counts filling in after the rows,
/// copying, and a failed read shown until a good one replaces it. Every path is fictional and none exists, so
/// Return copies instead of opening Finder.
@MainActor
final class LauncherWorktreesTests: XCTestCase {
    private var root: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("launcher-worktrees-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: root) }

    private let repo = "/Users/fictional/workspace/app"
    private var fictional: [Worktree] {
        [
            Worktree(repository: repo, path: repo + "/.claude/worktrees/small", branch: "feat/small", head: "1111111111"),
            Worktree(repository: repo, path: repo + "/.claude/worktrees/served", branch: "feat/served", head: "2222222222"),
            Worktree(repository: repo, path: repo + "/dist-release.ship-9.9.9.x/worktree", branch: nil, head: "3333333333"),
            Worktree(repository: repo, path: "/Users/fictional/gone", branch: "old", head: "4444444444", stale: true),
        ]
    }

    private func model() -> LauncherModel {
        let model = LauncherModel(index: AppIndex(entries: []),
            clipboard: ClipboardStore(retention: 10, storageURL: root.appendingPathComponent("clips.sqlite"), encryptionKey: SymmetricKey(size: .bits256)),
            notes: NotesStore(directory: root.appendingPathComponent("Notes")), config: Preferences(),
            usage: UsageStore(url: root.appendingPathComponent("usage.sqlite")), files: FileSearch(home: .unavailable)) { _ in }
        model.searchesSecondarySources = false
        model.appleShortcuts.loadOverride = { $0([], nil) }
        model.servers.loadOverride = { [repo] in
            $0([ListeningServer(pid: 4101, port: 3000, process: "node", executable: "/opt/fictional/bin/node", directory: repo + "/.claude/worktrees/served/web", exposed: false)], nil)
        }
        model.dismiss = {}
        return model
    }

    private func settle() async { try? await Task.sleep(nanoseconds: 80_000_000) }

    func testSectionsSizesLabelsAndCopies() async throws {
        let model = model()
        var copied: [String] = []
        model.copyText = { copied.append($0) }
        model.worktrees.loadOverride = { [fictional] _, finish in finish(fictional, nil) }
        var measured: [[String]] = []
        model.worktrees.detailsOverride = { [repo] paths, finish in
            measured.append(paths)
            let sizes: [String: Int64] = [repo + "/.claude/worktrees/small": 1_000_000, repo + "/.claude/worktrees/served": 5_000_000,
                                          repo + "/dist-release.ship-9.9.9.x/worktree": 2_300_000_000]
            finish(Dictionary(uniqueKeysWithValues: paths.map { ($0, WorktreeDetails(size: sizes[$0], lastCommit: Date().addingTimeInterval(-86400 * 3))) }))
        }
        model.worktrees.changesOverride = { [repo] paths, finish in
            finish(Dictionary(uniqueKeysWithValues: paths.map { ($0, RepositoryState(changed: $0.hasSuffix("small") ? 2 : 0)) }))
            _ = repo
        }
        model.query = "worktrees"
        await settle()
        XCTAssertEqual(measured.flatMap { $0 }.count, 3, "Only existing worktrees are measured")
        XCTAssertFalse(measured.flatMap { $0 }.contains("/Users/fictional/gone"))
        XCTAssertEqual(model.sections.map(\.title), ["In Use", "Worktrees", "Stale"])
        XCTAssertEqual(model.rows.map(\.id), ["worktree:\(repo)/.claude/worktrees/served", "worktree:\(repo)/dist-release.ship-9.9.9.x/worktree",
                                              "worktree:\(repo)/.claude/worktrees/small", "worktree:/Users/fictional/gone"])
        XCTAssertEqual(model.rows.map(\.kind), ["In Use", "Clean", "Uncommitted", "Stale"])
        guard case .worktree(_, _, let served) = model.rows[0], case .worktree(let release, _, let releaseDetail) = model.rows[1],
              case .worktree(_, _, let small) = model.rows[2] else { return XCTFail("Worktree rows") }
        XCTAssertTrue(served.hasPrefix("Node.js on 3000 · app · "), served)
        XCTAssertTrue(releaseDetail.contains("2.3 GB"), releaseDetail)
        XCTAssertTrue(releaseDetail.hasSuffix("3d"), releaseDetail)
        XCTAssertTrue(small.contains("2 uncommitted"), small)
        XCTAssertEqual(release.title, "worktree · detached 3333333")

        model.selection = 1
        XCTAssertEqual(try XCTUnwrap(model.selectedRow).itemActions, [.reveal, .openInTerminal, .copyPath])
        model.activateSelection()
        XCTAssertEqual(copied.last, repo + "/dist-release.ship-9.9.9.x/worktree", "A missing folder is copied, not revealed")
        model.selection = 2
        model.activateSecondary()
        XCTAssertEqual(copied.last, repo + "/.claude/worktrees/small")
        let row = try XCTUnwrap(model.selectedRow)
        XCTAssertEqual(row.itemActions, [.reveal, .openInTerminal, .copyPath, .copyBranch])
        model.performAction(.copyBranch, target: row)
        XCTAssertEqual(copied.last, "feat/small")
        model.selection = 3
        XCTAssertEqual(try XCTUnwrap(model.selectedRow).itemActions, [.copyPath])
        XCTAssertNil(try XCTUnwrap(model.selectedRow).secondaryAction)

        model.query = "wt stale"
        await settle()
        XCTAssertEqual(model.rows.map(\.id), ["worktree:/Users/fictional/gone"])
        model.query = "wt release"
        await settle()
        XCTAssertEqual(model.rows.map(\.id), ["worktree:\(repo)/dist-release.ship-9.9.9.x/worktree"])
    }

    func testFailureIsShownUntilAGoodRead() async throws {
        let model = model()
        var pending: [([Worktree]?, String?) -> Void] = []
        model.worktrees.loadOverride = { _, finish in pending.append(finish) }
        model.worktrees.detailsOverride = { _, finish in finish([:]) }
        model.worktrees.changesOverride = { _, finish in finish([:]) }
        model.query = "worktrees"
        await settle()
        XCTAssertEqual(model.notice, "Looking for git worktrees…")
        model.worktrees.refresh(folders: [])
        XCTAssertEqual(pending.count, 1, "A read already in flight is not started twice")
        pending[0](nil, "Fictional read failure")
        await settle()
        XCTAssertEqual(model.notice, "Fictional read failure")

        model.worktrees.refresh(folders: [], force: true)
        XCTAssertEqual(pending.count, 2)
        pending[1]([], nil)
        await settle()
        XCTAssertEqual(model.notice, "No git worktrees found.", "A good read replaces the failure")
    }

    func testEmptyListSaysSoAndHintsAreAbsolute() async throws {
        let model = model()
        var hints: [[String]] = []
        model.worktrees.loadOverride = { folders, finish in hints.append(folders); finish([], nil) }
        model.query = "wt"
        await settle()
        XCTAssertEqual(model.notice, "No git worktrees found.")
        XCTAssertTrue(hints.flatMap { $0 }.allSatisfy { $0.hasPrefix("/") })
        model.query = "wt stale"
        await settle()
        XCTAssertEqual(model.notice, "No stale worktrees.")
    }
}
