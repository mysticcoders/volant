import XCTest
@testable import Volant

final class HerdrAttentionTests: XCTestCase {
    private func session(_ terminal: String = "one", status: String = "blocked", reference: String = "session") -> Volant.AgentSession {
        Volant.AgentSession(agent: "claude", agentStatus: status, paneID: "w1:p1", terminalID: terminal,
                     cwd: "/fictional/project", terminalTitle: nil, agentSession: .init(value: reference))
    }
    func testIdentityAndBlockedStateAreRequired() {
        let target = session()
        XCTAssertTrue(Volant.HerdrAttention.matches(target, in: [session()]))
        XCTAssertFalse(Volant.HerdrAttention.matches(target, in: [session("replacement")]))
        XCTAssertFalse(Volant.HerdrAttention.matches(target, in: [session(reference: "new-session")]))
        XCTAssertFalse(Volant.HerdrAttention.matches(target, in: [session(status: "working")]))
    }
    func testPreviewPreservesLiteralQuestionAndBoundsContent() throws {
        let text = "Allow **npm test**?\n1. Yes\n2. Yes, for this session\n3. No"
        XCTAssertEqual(try Volant.HerdrAttention.preview(Data(text.utf8)).text, text)
        let preview = try Volant.HerdrAttention.preview(Data(String(repeating: "row\n", count: 80).utf8))
        XCTAssertTrue(preview.truncated)
        XCTAssertEqual(preview.text.components(separatedBy: "\n").count, 30)
        XCTAssertThrowsError(try Volant.HerdrAttention.preview(Data(repeating: 65, count: 128_001)))
        XCTAssertThrowsError(try Volant.HerdrAttention.preview(Data([0xff])))
        XCTAssertEqual(try Volant.HerdrAttention.preview(Data("\u{202E}safe\u{0007}".utf8)).text, "safe")
    }
    func testDelayedPreviewCannotReplaceNewTargetOrDisconnectedState() {
        let model = AgentsModel()
        let first = session(), second = session("two")
        var replies: [(Data?, String?) -> Void] = []
        model.attentionReader = { _, reply in replies.append(reply) }
        model.connected = true; model.sessions = [first, second]
        model.watchAttention(first)
        model.watchAttention(second)
        replies[0](Data("old question".utf8), nil)
        replies[1](Data("current question".utf8), nil)
        let done = expectation(description: "main callbacks")
        DispatchQueue.main.async {
            XCTAssertEqual(model.attention?.text, "current question")
            model.refreshAttention()
            model.disconnect()
            replies[2](Data("late question".utf8), nil)
            DispatchQueue.main.async {
                XCTAssertNil(model.attention)
                XCTAssertFalse(model.attentionLoading)
                done.fulfill()
            }
        }
        wait(for: [done], timeout: 2)
    }
}
