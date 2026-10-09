import XCTest

@testable import VolantCore

/// Herdr panes sort by attention, then project, then identity, the order the launcher shows.
final class AgentSessionSortTests: XCTestCase {
    private func pane(_ status: String, _ cwd: String?, _ pane: String) -> AgentSession {
        AgentSession(agent: "claude", agentStatus: status, paneID: pane, terminalID: "t1", cwd: cwd)
    }

    func testWaitingPanesComeFirstThenProjectsInFinderOrder() {
        let panes = [
            pane("idle", "/tmp/fictional/alpha", "p1"),
            pane("working", "/tmp/fictional/Project10", "p2"),
            pane("blocked", "/tmp/fictional/zeta", "p3"),
            pane("working", "/tmp/fictional/Project9", "p4"),
            pane("unknown", nil, "p5"),
            pane("working", "/tmp/other/Project9", "p0"),
        ]
        XCTAssertEqual(AgentSession.sorted(panes).map(\.paneID), ["p3", "p0", "p4", "p2", "p1", "p5"])
    }

    func testSortingIsStableForRepeatedRefreshes() {
        let panes = (0..<200).map { pane(["blocked", "working", "idle"][$0 % 3], "/tmp/fictional/project-\($0 % 7)", "p\($0)") }
        let once = AgentSession.sorted(panes)
        XCTAssertEqual(AgentSession.sorted(once.reversed()).map(\.id), once.map(\.id))
    }

    func testProjectNamesComeFromThePathAlone() {
        XCTAssertEqual(pane("idle", "/tmp/fictional/Project Name/", "p1").project, "Project Name")
        XCTAssertEqual(pane("idle", "/nonexistent/fictional/alpha", "p1").project, "alpha")
        XCTAssertEqual(pane("idle", nil, "p1").project, "Unknown project")
    }
}
