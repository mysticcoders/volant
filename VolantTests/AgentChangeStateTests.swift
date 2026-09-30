import XCTest
import VolantCore
@testable import Volant

/// Unread state and repository counts for Herdr panes, driven through injected readers with
/// fictional panes and folders. No Herdr socket, helper or real repository is involved.
@MainActor
final class AgentChangeStateTests: XCTestCase {
    typealias Reply = (Data?, String?) -> Void
    private func drain() async { await withCheckedContinuation { continuation in DispatchQueue.main.async { continuation.resume() } } }
    private func pane(_ status: String, sequence: UInt64, cwd: String = "/fictional/app", id: String = "w1:p1", focused: Bool? = nil) -> AgentSession {
        var session = AgentSession(agent: "claude", agentStatus: status, paneID: id, terminalID: "term-" + id, cwd: cwd, stateChangeSequence: sequence)
        session.focused = focused
        return session
    }

    private func model(local: @escaping () -> [AgentSession], repositories: @escaping ([String], Reply) -> Void) -> AgentsModel {
        let model = AgentsModel()
        model.machineReader = { $0(try? JSONEncoder().encode([HerdrMachine]()), nil) }
        model.inventoryReader = { machine, reply in if machine == nil { reply(try? JSONEncoder().encode(local()), nil) } }
        model.repositoryReader = repositories
        model.connected = true
        return model
    }

    func testAPaneThatStopsWhileYouAreAwayIsUnreadUntilFocused() async throws {
        var panes = [pane("working", sequence: 4)]
        let model = model(local: { panes }, repositories: { _, reply in reply(try? JSONEncoder().encode([String: RepositoryState]()), nil) })
        model.refresh(); await drain(); await drain()
        XCTAssertFalse(model.isUnread(model.sessions[0]), "a pane seen for the first time starts read")
        panes = [pane("working", sequence: 6)]
        model.refresh(); await drain(); await drain()
        XCTAssertFalse(model.isUnread(model.sessions[0]), "still working is not waiting on you")
        panes = [pane("done", sequence: 7)]
        model.refresh(); await drain(); await drain()
        XCTAssertTrue(model.isUnread(model.sessions[0]))
        XCTAssertEqual(model.unreadCount, 1)
        model.markSeen(model.sessions[0])
        XCTAssertFalse(model.isUnread(model.sessions[0]))
        panes = [pane("blocked", sequence: 9)]
        model.refresh(); await drain(); await drain()
        XCTAssertTrue(model.isUnread(model.sessions[0]))
        panes = [pane("blocked", sequence: 9, focused: true)]
        model.refresh(); await drain(); await drain()
        XCTAssertFalse(model.isUnread(model.sessions[0]), "looking at the pane in Herdr counts as reading it")
    }

    func testRepositoriesAreSharedPerFolderAndOnlyReReadWhenAPaneChanges() async throws {
        var panes = [pane("working", sequence: 1, id: "w1:p1"), pane("idle", sequence: 3, id: "w1:p2"), pane("idle", sequence: 1, cwd: "/fictional/site", id: "w1:p3")]
        var requests: [[String]] = []
        let model = model(local: { panes }, repositories: { paths, reply in
            requests.append(paths)
            reply(try? JSONEncoder().encode(["/fictional/app": RepositoryState(branch: "main", ahead: 1, changed: 3)]), nil)
        })
        model.refresh(); await drain(); await drain()
        XCTAssertEqual(requests, [["/fictional/app", "/fictional/site"]], "one request, each folder once")
        XCTAssertEqual(model.repository(for: model.sessions.first { $0.paneID == "w1:p2" }!)?.summary, "main · 3 changed · 1 ahead")
        XCTAssertNil(model.repository(for: model.sessions.first { $0.paneID == "w1:p3" }!), "a folder that is not a repository has no state")
        model.refresh(); await drain(); await drain()
        XCTAssertEqual(requests.count, 1, "unchanged panes do not rerun git")
        panes[0] = pane("done", sequence: 5, id: "w1:p1")
        model.refresh(); await drain(); await drain()
        XCTAssertEqual(requests.last, ["/fictional/app"], "only the folder whose pane changed is read again")
    }

    func testRemotePanesAreNeverInspectedAndLateRepliesAreDropped() async throws {
        var pending: Reply?
        let model = model(local: { [self.pane("idle", sequence: 2)] }, repositories: { _, reply in pending = reply })
        model.refresh(); await drain(); await drain()
        var remote = pane("idle", sequence: 2)
        remote.machine = HerdrMachine(id: "build", label: "Build Mac", target: "fictional", session: "default", enabled: true)
        XCTAssertNil(model.repository(for: remote))
        model.disconnect()
        pending?(try JSONEncoder().encode(["/fictional/app": RepositoryState(branch: "main")]), nil); await drain()
        XCTAssertTrue(model.repositories.isEmpty)
    }

    func testDetectionSortsReadyAgentsFirstAndReportsFailures() async throws {
        let detection = ACPAgentDetection()
        detection.reader = { reply in
            reply(try? JSONEncoder().encode([
                ACPAgentAvailability(provider: "gemini", state: .notInstalled, detail: "Gemini CLI was not found.", path: nil),
                ACPAgentAvailability(provider: "codex", state: .needsAdapter, detail: "Adapter missing.", path: nil),
                ACPAgentAvailability(provider: "qwen", state: .ready, detail: "Found at /opt/homebrew/bin/qwen", path: "/opt/homebrew/bin/qwen")
            ]), nil)
        }
        detection.detect(); await drain()
        XCTAssertEqual(detection.agents.map(\.provider), ["qwen", "codex", "gemini"])
        detection.reader = { $0(nil, "The agent helper is unavailable.") }
        detection.detect(); await drain()
        XCTAssertEqual(detection.message, "The agent helper is unavailable.")
    }
}
