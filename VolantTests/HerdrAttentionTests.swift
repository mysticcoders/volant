import XCTest
import VolantCore
@testable import Volant

final class HerdrAttentionTests: XCTestCase {
    private func session(_ terminal: String = "one", status: String = "blocked", reference: String = "session") -> VolantCore.AgentSession {
        VolantCore.AgentSession(agent: "claude", agentStatus: status, paneID: "w1:p1", terminalID: terminal,
                     cwd: "/fictional/project", terminalTitle: nil, agentSession: .init(value: reference))
    }
    func testIdentityAndBlockedStateAreRequired() {
        let target = session()
        XCTAssertTrue(VolantCore.HerdrAttention.matches(target, in: [session()]))
        XCTAssertFalse(VolantCore.HerdrAttention.matches(target, in: [session("replacement")]))
        XCTAssertFalse(VolantCore.HerdrAttention.matches(target, in: [session(reference: "new-session")]))
        XCTAssertFalse(VolantCore.HerdrAttention.matches(target, in: [session(status: "working")]))
    }
    func testPreviewPreservesLiteralQuestionAndBoundsContent() throws {
        let text = "Allow **npm test**?\n1. Yes\n2. Yes, for this session\n3. No"
        XCTAssertEqual(try VolantCore.HerdrAttention.preview(Data(text.utf8)).text, text)
        let preview = try VolantCore.HerdrAttention.preview(Data(String(repeating: "row\n", count: 80).utf8))
        XCTAssertTrue(preview.truncated)
        XCTAssertEqual(preview.text.components(separatedBy: "\n").count, 30)
        XCTAssertThrowsError(try VolantCore.HerdrAttention.preview(Data(repeating: 65, count: 128_001)))
        XCTAssertThrowsError(try VolantCore.HerdrAttention.preview(Data([0xff])))
        XCTAssertEqual(try VolantCore.HerdrAttention.preview(Data("\u{202E}safe\u{0007}".utf8)).text, "safe")
    }
    private func snapshot(_ text: String) -> Data {
        try! JSONEncoder().encode(Volant.HerdrResponseController.Snapshot(text: text, token: nil, question: nil))
    }
    func testDelayedPreviewCannotReplaceNewTargetOrDisconnectedState() {
        let model = AgentsModel()
        let first = session(), second = session("two")
        var replies: [(Data?, String?) -> Void] = []
        model.attentionReader = { _, reply in replies.append(reply) }
        model.connected = true; model.sessions = [first, second]
        model.watchAttention(first)
        model.watchAttention(second)
        replies[0](self.snapshot("old question"), nil)
        replies[1](self.snapshot("current question"), nil)
        let done = expectation(description: "main callbacks")
        DispatchQueue.main.async {
            XCTAssertEqual(model.attention?.text, "current question")
            model.refreshAttention()
            model.disconnect()
            replies[2](self.snapshot("late question"), nil)
            DispatchQueue.main.async {
                XCTAssertNil(model.attention)
                XCTAssertFalse(model.attentionLoading)
                done.fulfill()
            }
        }
        wait(for: [done], timeout: 2)
    }
}
