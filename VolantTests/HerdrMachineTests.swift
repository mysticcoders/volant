import XCTest
@testable import Volant

final class HerdrMachineTests: XCTestCase {
    private let remote = HerdrMachine(id: "remote-one", label: "Build Mac", target: "fictional-host", session: "agents", enabled: true)
    private func list(_ status: String = "blocked") throws -> Data {
        try JSONSerialization.data(withJSONObject: ["result": ["agents": [["agent": "codex", "agent_status": status,
            "pane_id": "w1:p1", "terminal_id": "same-terminal", "state_change_seq": 4]]]])
    }
    func testSamePaneOnDifferentMachinesHasDifferentIdentity() throws {
        let local = try AgentSession.decodeList(list())[0]
        let remote = try AgentSession.decodeList(list(), machine: remote)[0]
        XCTAssertNotEqual(local.id, remote.id)
        XCTAssertFalse(HerdrAttention.matches(local, in: [remote]))
        XCTAssertFalse(HerdrAttention.matches(remote, in: [local]))
        XCTAssertEqual(try JSONDecoder().decode(AgentSession.self, from: JSONEncoder().encode(remote)), remote)
    }
    func testRoutingRevalidatesProfileBeforeEveryOperation() throws {
        var catalog = [remote], calls: [[String]] = []
        let router = HerdrMachineRouter { args in
            if args == ["machine", "list", "--json"] { return try JSONEncoder().encode(catalog) }
            calls.append(args); return Data()
        }
        _ = try router.execute(remote, ["agent", "read", "w1:p1"])
        XCTAssertEqual(calls, [["--machine", remote.id, "agent", "read", "w1:p1"]])
        for replacement in [
            HerdrMachine(id: remote.id, label: remote.label, target: "different-host", session: remote.session, enabled: true),
            HerdrMachine(id: remote.id, label: remote.label, target: remote.target, session: "other-session", enabled: true),
            HerdrMachine(id: remote.id, label: remote.label, target: remote.target, session: remote.session, enabled: false)
        ] {
            catalog = [replacement]
            XCTAssertThrowsError(try router.execute(remote, ["agent", "send-keys", "w1:p1", "enter"]))
        }
        catalog = []
        XCTAssertThrowsError(try router.execute(remote, ["agent", "focus", "w1:p1"]))
        XCTAssertEqual(calls.count, 1)
    }
    func testUnavailableRemoteKeepsLocalResultsAndNeverFallsBack() throws {
        let catalog = try JSONEncoder().encode([remote])
        let local = try list("working")
        let router = HerdrMachineRouter { args in
            if args == ["machine", "list", "--json"] { return catalog }
            if args == ["agent", "list"] { return local }
            throw CocoaError(.fileReadNoSuchFile)
        }
        let result = router.inventory()
        XCTAssertEqual(result.agents.count, 1)
        XCTAssertNil(result.agents[0].machine)
        XCTAssertEqual(result.machines.map(\.state), ["connected", "unavailable"])
        XCTAssertThrowsError(try router.execute(remote, ["agent", "send-keys", "w1:p1", "enter"]))
    }
    func testUnavailableLocalKeepsRemoteAndDisabledMachinesAreNotQueried() throws {
        let disabled = HerdrMachine(id: "disabled", label: "Offline", target: "disabled-host", session: "default", enabled: false)
        let catalog = try JSONEncoder().encode([remote, disabled]), agents = try list()
        let router = HerdrMachineRouter { args in
            if args == ["machine", "list", "--json"] { return catalog }
            if args == ["--machine", self.remote.id, "agent", "list"] { return agents }
            XCTAssertEqual(args, ["agent", "list"])
            throw CocoaError(.fileReadNoSuchFile)
        }
        let result = router.inventory()
        XCTAssertEqual(result.agents.first?.machine, remote)
        XCTAssertEqual(result.machines.map(\.state), ["unavailable", "connected", "disabled"])
    }
    func testRemoteAnswerTokenNeverTargetsIdenticalLocalPane() throws {
        var status = "blocked", keys: [[String]] = []
        let controller = HerdrResponseController(runOnMachine: { machine, args in
            XCTAssertEqual(machine?.routeIdentity, self.remote.routeIdentity)
            switch args[1] {
            case "list": return try self.list(status)
            case "read": return Data(HerdrResponseTests.question.utf8)
            case "send-keys": keys.append(args); status = "working"; return Data()
            default: throw CocoaError(.featureUnsupported)
            }
        })
        let target = try AgentSession.decodeList(list(), machine: remote)[0]
        let token = try XCTUnwrap(controller.read(target).token)
        XCTAssertTrue(try controller.respond(token: token, choice: 1).contains("resumed"))
        XCTAssertEqual(keys, [["agent", "send-keys", "w1:p1", "enter"]])
        XCTAssertThrowsError(try controller.respond(token: token, choice: 1))
        XCTAssertEqual(keys.count, 1)
    }
    func testCatalogRejectsAmbiguousIDs() throws {
        XCTAssertThrowsError(try HerdrMachine.decode(JSONEncoder().encode([remote, remote])))
    }
    func testProcessOutputAndTimeoutAreBounded() throws {
        let home = FileManager.default.temporaryDirectory.path
        let result = try HerdrProcess.run(executable: URL(fileURLWithPath: "/usr/bin/printf"), arguments: ["fictional"], home: home)
        XCTAssertEqual(String(data: result, encoding: .utf8), "fictional")
        let start = Date()
        XCTAssertThrowsError(try HerdrProcess.run(executable: URL(fileURLWithPath: "/bin/sleep"), arguments: ["30"], home: home, timeout: 0.1))
        XCTAssertLessThan(Date().timeIntervalSince(start), 3)
    }

}
