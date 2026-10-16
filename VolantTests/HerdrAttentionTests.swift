import XCTest
import VolantCore
@testable import Volant

final class HerdrAttentionTests: XCTestCase {
    private func session(_ terminal: String = "one", status: String = "blocked", reference: String = "session") -> VolantCore.AgentSession {
        VolantCore.AgentSession(agent: "claude", agentStatus: status, paneID: "w1:p1", terminalID: terminal,
                     cwd: "/fictional/project", terminalTitle: nil, agentSession: .init(value: reference))
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
