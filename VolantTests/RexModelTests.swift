import Combine
import CryptoKit
import XCTest
import VolantCore
@testable import Volant

/// The Rex model and `rex` launcher view, driven by an injected watcher reader with fictional panes.
/// These do not reach a Rex server or the signed agent helper.
@MainActor
final class RexModelTests: XCTestCase {
    typealias Reply = (Data?, Int, String?) -> Void
    private func drain() async { await withCheckedContinuation { continuation in DispatchQueue.main.async { continuation.resume() } } }
    private func pane(_ block: String, session: String = "session:fictional", label: String = "orbit", state: RexState?, message: String? = nil) -> RexPane {
        RexPane(sessionID: session, sessionLabel: label, blockID: block, label: "shell", cwd: "/fictional/" + label,
                status: state.map { RexStatus(state: $0, app: "claude-code", message: message) })
    }
    private func encode(_ panes: [RexPane]) throws -> Data { try JSONEncoder().encode(RexInventory(panes: RexInventory.sorted(panes))) }

    func testRepliesAfterADisconnectAreDroppedAndDisconnectStopsTheWatcher() async throws {
        let rex = RexModel()
        var replies: [Reply] = [], asked: [Int] = [], stops = 0
        rex.reader = { known, reply in asked.append(known); replies.append(reply) }
        rex.stopper = { stops += 1 }
        rex.connect()
        rex.refresh()
        XCTAssertEqual(replies.count, 1, "a tick waits while a read is outstanding")
        rex.disconnect()
        XCTAssertEqual(stops, 1)
        rex.connect()
        replies[0](try encode([pane("block:old", state: .blocked)]), 1, nil)
        await drain()
        XCTAssertTrue(rex.panes.isEmpty, "a reply from before the reconnect must not appear")
        replies[1](try encode([pane("block:new", state: .working)]), 1, nil)
        await drain()
        XCTAssertEqual(rex.panes.map(\.blockID), ["block:new"])
        XCTAssertEqual(asked, [-1, -1, 1], "each connection starts from no revision, and a reply starts the next read")
        rex.disconnect()
    }

    func testUnchangedRevisionKeepsPanesAndStartingShowsLoading() async throws {
        let rex = RexModel()
        var reply: Reply?, asked: [Int] = []
        rex.reader = { known, next in asked.append(known); reply = next }
        rex.stopper = {}
        rex.connect()
        reply?(nil, 0, nil)
        await drain()
        XCTAssertTrue(rex.loading)
        XCTAssertEqual(rex.message, "Loading Rex panes…")
        rex.refresh()
        XCTAssertEqual(asked, [-1, 0], "the next read starts with the reply, and a tick adds none while it is outstanding")
        reply?(try encode([pane("block:a", state: .blocked)]), 1, nil)
        await drain()
        reply?(nil, 1, nil)
        await drain()
        XCTAssertEqual(rex.panes.count, 1, "a reply at the held revision changes nothing")
        XCTAssertFalse(rex.loading)
        XCTAssertEqual(asked, [-1, 0, 1, 1])
        rex.disconnect()
    }

    func testNotRunningStaysConnectedAndRecovers() async throws {
        let rex = RexModel()
        var reply: Reply?
        rex.reader = { _, next in reply = next }
        rex.stopper = {}
        rex.connect()
        reply?(nil, 1, "Rex isn’t running. Open Rex, then try again.")
        await drain()
        XCTAssertTrue(rex.connected)
        XCTAssertEqual(rex.message, "Rex isn’t running. Open Rex, then try again.")
        reply?(try encode([pane("block:a", state: .idle)]), 2, nil)
        await drain()
        XCTAssertNil(rex.problem)
        XCTAssertEqual(rex.panes.count, 1)
        rex.disconnect()
    }

    func testFocusRefusesAPaneNoLongerListedAndActivatesRexOnSuccess() async throws {
        let rex = RexModel()
        var reply: Reply?
        var focused: [String] = []
        var activations = 0
        rex.reader = { _, next in reply = next }
        rex.stopper = {}
        rex.focuser = { pane, done in focused.append(pane.id); done(nil) }
        rex.activateRex = { activations += 1 }
        rex.connect()
        let listed = pane("block:a", state: .blocked)
        reply?(try encode([listed]), 1, nil)
        await drain()
        var result: String?? = .none
        rex.focus(pane("block:gone", state: .blocked)) { result = .some($0) }
        XCTAssertEqual(result, .some("This pane changed or closed. Refresh before continuing."))
        XCTAssertTrue(focused.isEmpty)
        rex.focus(listed) { result = .some($0) }
        await drain()
        XCTAssertEqual(focused, [listed.id])
        XCTAssertEqual(activations, 1)
        XCTAssertEqual(result, .some(nil))
        rex.disconnect()
    }

    func testRexQueryListsWaitingPanesFirstAndFilters() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let rex = RexModel()
        var reply: Reply?
        rex.reader = { _, next in reply = next }
        rex.stopper = {}
        let model = LauncherModel(index: AppIndex(entries: []), clipboard: ClipboardStore(retention: 2, storageURL: root.appendingPathComponent("clips.sqlite"), encryptionKey: SymmetricKey(size: .bits256)),
                                  notes: NotesStore(directory: root.appendingPathComponent("Notes")), config: Preferences(),
                                  usage: UsageStore(url: root.appendingPathComponent("usage.sqlite")), files: FileSearch(startQuery: { _ in false }), rex: rex) { _ in }
        model.searchesSecondarySources = false
        model.query = "safari"
        XCTAssertFalse(rex.connected, "Rex is read only from the rex view or its footer status")
        model.query = "rex"
        XCTAssertTrue(rex.connected)
        reply?(try encode([pane("block:a", label: "comet", state: .working), pane("block:b", label: "orbit", state: .blocked, message: "Approve the deploy?")]), 1, nil)
        await drain(); await drain()
        XCTAssertEqual(model.rows.map(\.id), ["rex:session:fictional/block:b", "rex:session:fictional/block:a"])
        XCTAssertEqual(model.selectedRow?.primaryAction, "Focus in Rex")
        model.query = "rex deploy"
        XCTAssertEqual(model.rows.map(\.id), ["rex:session:fictional/block:b"])
        XCTAssertTrue(LauncherRouting.isReserved("rex"))
        rex.disconnect()
    }
}
