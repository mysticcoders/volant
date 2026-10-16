import XCTest

@testable import VolantCore

/// A blocked pane is answered only while its identity and blocked state still match, its preview
/// is bounded and stripped of control characters, and the saved machine list rejects duplicate IDs.
final class HerdrAttentionTests: XCTestCase {
    private func session(_ terminal: String = "one", status: String = "blocked", reference: String = "session") -> AgentSession {
        AgentSession(agent: "claude", agentStatus: status, paneID: "w1:p1", terminalID: terminal,
                     cwd: "/fictional/project", terminalTitle: nil, agentSession: .init(value: reference))
    }

    func testIdentityAndBlockedStateAreRequired() {
        let target = session()
        XCTAssertTrue(HerdrAttention.matches(target, in: [session()]))
        XCTAssertFalse(HerdrAttention.matches(target, in: [session("replacement")]))
        XCTAssertFalse(HerdrAttention.matches(target, in: [session(reference: "new-session")]))
        XCTAssertFalse(HerdrAttention.matches(target, in: [session(status: "working")]))
    }

    func testPreviewPreservesLiteralQuestionAndBoundsContent() throws {
        let text = "Allow **npm test**?\n1. Yes\n2. Yes, for this session\n3. No"
        XCTAssertEqual(try HerdrAttention.preview(Data(text.utf8)).text, text)
        let preview = try HerdrAttention.preview(Data(String(repeating: "row\n", count: 80).utf8))
        XCTAssertTrue(preview.truncated)
        XCTAssertEqual(preview.text.components(separatedBy: "\n").count, 30)
        XCTAssertThrowsError(try HerdrAttention.preview(Data(repeating: 65, count: 128_001)))
        XCTAssertThrowsError(try HerdrAttention.preview(Data([0xff])))
        XCTAssertEqual(try HerdrAttention.preview(Data("\u{202E}safe\u{0007}".utf8)).text, "safe")
    }

    func testMachineCatalogRejectsAmbiguousIDs() throws {
        let remote = HerdrMachine(id: "remote-one", label: "Build Mac", target: "fictional-host", session: "agents", enabled: true)
        XCTAssertThrowsError(try HerdrMachine.decode(JSONEncoder().encode([remote, remote])))
    }
}
