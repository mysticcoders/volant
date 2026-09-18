import XCTest
@testable import Volant

@MainActor
final class HerdrLoadingTests: XCTestCase {
    typealias Reply = (Data?, String?) -> Void
    private let remote = HerdrMachine(id: "build", label: "Build Mac", target: "fictional", session: "default", enabled: true)
    private func drain() async { await withCheckedContinuation { continuation in DispatchQueue.main.async { continuation.resume() } } }
    private func panes(_ machine: HerdrMachine? = nil) throws -> Data {
        var pane = AgentSession(agent: "codex", agentStatus: "working", paneID: "w1:p1", terminalID: "same-terminal", cwd: "/fictional/project", terminalTitle: nil, agentSession: nil)
        pane.machine = machine
        return try JSONEncoder().encode([pane])
    }
    func testLocalPublishesBeforeCatalogAndKeepsRefreshingWhileRemoteWaits() async throws {
        let model = AgentsModel()
        var catalog: Reply?, local: Reply?, remoteReply: Reply?
        var remoteCalls = 0
        model.machineReader = { catalog = $0 }
        model.inventoryReader = { machine, reply in
            if machine == nil { local = reply } else { remoteCalls += 1; remoteReply = reply }
        }
        model.connected = true
        model.refresh()
        local?(try panes(), nil); await drain()
        XCTAssertEqual(model.sessions.count, 1)
        XCTAssertTrue(model.busy) // Catalog has not returned yet.
        catalog?(try JSONEncoder().encode([remote]), nil); await drain()
        XCTAssertEqual(model.machines.map(\.state), ["connected", "loading"])
        XCTAssertEqual(remoteCalls, 1)
        model.refresh()
        local?(try JSONEncoder().encode([AgentSession]()), nil); await drain()
        XCTAssertTrue(model.sessions.isEmpty) // A fresh Local result did not wait for remote.
        XCTAssertEqual(remoteCalls, 1) // No duplicate request for an in-flight machine.
        catalog?(try JSONEncoder().encode([remote]), nil); await drain()
        remoteReply?(try panes(remote), nil); await drain()
        XCTAssertEqual(model.sessions.first?.machine?.routeIdentity, remote.routeIdentity)
        XCTAssertFalse(model.busy)
    }
    func testFailureClearsOnlyThatMachineAndDisconnectRejectsLateReplies() async throws {
        let model = AgentsModel()
        var catalog: Reply?, local: Reply?, remoteReply: Reply?
        model.machineReader = { catalog = $0 }
        model.inventoryReader = { machine, reply in if machine == nil { local = reply } else { remoteReply = reply } }
        model.connected = true; model.refresh()
        catalog?(try JSONEncoder().encode([remote]), nil); await drain()
        local?(try panes(), nil); remoteReply?(try panes(remote), nil); await drain()
        XCTAssertEqual(model.sessions.count, 2)
        model.refresh()
        remoteReply?(nil, "Unavailable"); await drain()
        XCTAssertEqual(model.sessions.count, 1)
        XCTAssertNil(model.sessions.first?.machine)
        XCTAssertEqual(model.machines.last?.state, "unavailable")
        model.disconnect()
        local?(try panes(), nil); catalog?(try JSONEncoder().encode([remote]), nil); await drain()
        XCTAssertTrue(model.sessions.isEmpty)
        XCTAssertTrue(model.machines.isEmpty)
        XCTAssertFalse(model.busy)
    }
    func testRetargetedMachineRejectsOldReply() async throws {
        let model = AgentsModel()
        var catalog: Reply?, remoteReplies: [Reply] = []
        model.machineReader = { catalog = $0 }
        model.inventoryReader = { machine, reply in if machine != nil { remoteReplies.append(reply) } }
        model.connected = true; model.refresh()
        catalog?(try JSONEncoder().encode([remote]), nil); await drain()
        model.refresh()
        let changed = HerdrMachine(id: remote.id, label: remote.label, target: "different-fictional-host", session: remote.session, enabled: true)
        catalog?(try JSONEncoder().encode([changed]), nil); await drain()
        XCTAssertEqual(remoteReplies.count, 2)
        remoteReplies[0](try panes(remote), nil); await drain()
        XCTAssertTrue(model.sessions.isEmpty)
        XCTAssertEqual(model.machines.last?.state, "loading")
        remoteReplies[1](try panes(changed), nil); await drain()
        XCTAssertEqual(model.sessions.first?.machine?.routeIdentity, changed.routeIdentity)
    }
}
