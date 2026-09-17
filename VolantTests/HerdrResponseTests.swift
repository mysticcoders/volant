import XCTest
@testable import Volant

final class HerdrResponseTests: XCTestCase {
    static let question = """
      Question 1/1 (1 unanswered)
      Which fictional theme should the demo use?

      › 1. Amber              warm colors
        2. Violet             cool colors
        3. None of the above  Optionally, add details in notes (tab).

      tab to add notes | enter to submit answer | esc to interrupt
    """
    private final class Terminal {
        var text = HerdrResponseTests.question
        var sequence = 10
        var status = "blocked"
        var terminal = "test-terminal"
        var keys: [[String]] = []
        var changeAfterSelection = false
        func run(_ args: [String]) throws -> Data {
            switch args[1] {
            case "list":
                return try JSONSerialization.data(withJSONObject: ["result": ["agents": [[
                    "agent": "codex", "agent_status": status, "pane_id": "w1:p1",
                    "terminal_id": terminal, "state_change_seq": sequence
                ]]]])
            case "read": return Data(text.utf8)
            case "send-keys":
                let sent = Array(args.dropFirst(3)); keys.append(sent)
                if sent == ["down"] {
                    text = text.replacingOccurrences(of: "› 1.", with: "  1.").replacingOccurrences(of: "  2.", with: "› 2.")
                    if changeAfterSelection { text = text.replacingOccurrences(of: "fictional theme", with: "different theme") }
                }
                if sent == ["enter"] { status = "working"; sequence += 1 }
                return Data()
            default: throw CocoaError(.featureUnsupported)
            }
        }
        func target() throws -> Volant.AgentSession { try Volant.AgentSession.decodeList(run(["agent", "list"]))[0] }
    }
    func testObservedCodexQuestionAndUnsupportedScreens() throws {
        let parsed = try XCTUnwrap(Volant.HerdrQuestion.parse(Self.question, provider: "codex"))
        XCTAssertEqual(parsed.answerChoices.map(\.label), ["Amber", "Violet"])
        XCTAssertEqual(parsed.selected, 1)
        XCTAssertNil(Volant.HerdrQuestion.parse(Self.question, provider: "claude"))
        XCTAssertNil(Volant.HerdrQuestion.parse(Self.question + "\nnew terminal output", provider: "codex"))
        XCTAssertNil(Volant.HerdrQuestion.parse(Self.question.replacingOccurrences(of: "warm colors", with: "warm\ncolors"), provider: "codex"))
        XCTAssertNil(Volant.HerdrQuestion.parse(Self.question.replacingOccurrences(of: "› 1.", with: "  1."), provider: "codex"))
    }
    func testVerifiedSelectionThenSubmitAndNoDuplicate() throws {
        let terminal = Terminal(), controller = Volant.HerdrResponseController(run: { try terminal.run($0) })
        let snapshot = try controller.read(terminal.target())
        let token = try XCTUnwrap(snapshot.token)
        XCTAssertEqual(try controller.respond(token: token, choice: 2), "Answer sent; Codex resumed.")
        XCTAssertEqual(terminal.keys, [["down"], ["enter"]])
        XCTAssertThrowsError(try controller.respond(token: token, choice: 2))
        XCTAssertEqual(terminal.keys.count, 2)
    }
    func testChangedPaneStateOrQuestionNeverSendsInput() throws {
        for mutation in 0..<3 {
            let terminal = Terminal(), controller = Volant.HerdrResponseController(run: { try terminal.run($0) })
            let token = try XCTUnwrap(controller.read(terminal.target()).token)
            if mutation == 0 { terminal.terminal = "replacement" }
            if mutation == 1 { terminal.sequence += 1 }
            if mutation == 2 { terminal.text = terminal.text.replacingOccurrences(of: "fictional theme", with: "new theme") }
            XCTAssertThrowsError(try controller.respond(token: token, choice: 2))
            XCTAssertTrue(terminal.keys.isEmpty)
        }
    }
    func testChangedQuestionAfterNavigationNeverSubmitsOrRetries() throws {
        let terminal = Terminal(), controller = Volant.HerdrResponseController(run: { try terminal.run($0) })
        terminal.changeAfterSelection = true
        let token = try XCTUnwrap(controller.read(terminal.target()).token)
        XCTAssertThrowsError(try controller.respond(token: token, choice: 2))
        XCTAssertEqual(terminal.keys, [["down"]])
        terminal.text = Self.question
        XCTAssertNil(try controller.read(terminal.target()).token)
    }
    func testExpiredAndNotesChoiceCannotSend() throws {
        for expired in [false, true] {
            let terminal = Terminal(), controller = Volant.HerdrResponseController(run: { try terminal.run($0) })
            let date = Date(); controller.now = { date }
            let token = try XCTUnwrap(controller.read(terminal.target()).token)
            if expired { controller.now = { date.addingTimeInterval(31) } }
            XCTAssertThrowsError(try controller.respond(token: token, choice: expired ? 1 : 3))
            XCTAssertTrue(terminal.keys.isEmpty)
        }
    }
}
