import XCTest
import VolantCore
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
        var provider = "codex"
        var terminal = "test-terminal"
        var keys: [[String]] = []
        var changeAfterSelection = false
        var confirmationRace = false
        var confirmationLists = 0
        func run(_ args: [String]) throws -> Data {
            switch args[1] {
            case "list":
                if confirmationRace, keys.contains(["enter"]) {
                    confirmationLists += 1
                    status = confirmationLists == 1 ? "blocked" : "working"
                }
                return try JSONSerialization.data(withJSONObject: ["result": ["agents": [[
                    "agent": provider, "agent_status": status, "pane_id": "w1:p1",
                    "terminal_id": terminal, "state_change_seq": sequence
                ]]]])
            case "read": return Data(text.utf8)
            case "send-keys":
                let sent = Array(args.dropFirst(3)); keys.append(sent)
                if provider == "claude", sent.allSatisfy({ $0 == "down" }) {
                    let destination = sent.count + 1
                    text = text.replacingOccurrences(of: "❯ 1.", with: "  1.")
                        .replacingOccurrences(of: "  \(destination).", with: "❯ \(destination).")
                }
                if provider == "codex", sent == ["down"] {
                    text = text.replacingOccurrences(of: "› 1.", with: "  1.").replacingOccurrences(of: "  2.", with: "› 2.")
                    if changeAfterSelection { text = text.replacingOccurrences(of: "fictional theme", with: "different theme") }
                }
                if sent == ["enter"] { status = "working"; sequence += 1 }
                return Data()
            default: throw CocoaError(.featureUnsupported)
            }
        }
        func target() throws -> VolantCore.AgentSession { try VolantCore.AgentSession.decodeList(run(["agent", "list"]))[0] }
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
    static let claudeQuestion = """
    ─────────────────────────────────────────────
     ☐ Theme

    Which fictional theme should the demo use?

    ❯ 1. Amber
         Warm colors
      2. Violet
         Cool colors
      3. Type something.
    ─────────────────────────────────────────────
      4. Chat about this

    Enter to select · ↑/↓ to navigate · Esc to cancel
    """
    static let claudePermission = """
    ─────────────────────────────────────────────
     Create file
     /fictional/approval.txt
    ╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌
      1 Violet demo
    ╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌
     Do you want to create approval.txt?
     ❯ 1. Yes
       2. Yes, and switch to accept edits (auto-approve file edits and common file
          commands) for this session (shift+tab)
       3. No

     Esc to cancel · Tab to amend
    """
    static let claudeBash = """
    Bash command

      printf 'VOLANT_CLAUDE_OK\\n'
      Print test marker string

    Permission rule Bash requires confirmation for this command.
    /permissions to update rules

    Do you want to proceed?
    ❯ 1. Yes
      2. No

    Esc to cancel · Tab to amend
    """
    func testClaudeQuestionAndPermissionPreserveExactScope() throws {
        let question = try XCTUnwrap(Volant.HerdrQuestion.parse(Self.claudeQuestion, provider: "claude"))
        XCTAssertEqual(question.answerChoices.map(\.label), ["Amber", "Violet"])
        XCTAssertEqual(question.answerChoices[1].detail, "Cool colors")
        let permission = try XCTUnwrap(Volant.HerdrQuestion.parse(Self.claudePermission, provider: "claude"))
        XCTAssertEqual(permission.answerChoices.count, 3)
        XCTAssertTrue(permission.choices[1].label.contains("for this session"))
        XCTAssertTrue(permission.choices[1].label.contains("common file commands"))
        XCTAssertTrue(permission.context?.contains("Violet demo") == true)
        let changed = Self.claudePermission.replacingOccurrences(of: "Violet demo", with: "Changed content")
        XCTAssertNotEqual(permission.fingerprint, Volant.HerdrQuestion.parse(changed, provider: "claude")?.fingerprint)
        XCTAssertNil(Volant.HerdrQuestion.parse(Self.claudePermission.replacingOccurrences(of: "Create file", with: ""), provider: "claude"))
        XCTAssertNil(Volant.HerdrQuestion.parse(Self.claudePermission.replacingOccurrences(of: "Violet demo", with: "… truncated"), provider: "claude"))
        XCTAssertNil(Volant.HerdrQuestion.parse(Self.claudeQuestion.replacingOccurrences(of: "☐ Theme", with: "☐ Theme ☐ Color"), provider: "claude"))
        XCTAssertNil(Volant.HerdrQuestion.parse(Self.claudeQuestion + "\nnew output", provider: "claude"))
    }
    func testClaudeQuestionYesAndNoUseVerifiedSelection() throws {
        for (screen, choice) in [(Self.claudeQuestion, 2), (Self.claudePermission, 1), (Self.claudePermission, 3), (Self.claudeBash, 1), (Self.claudeBash, 2)] {
            let terminal = Terminal(); terminal.provider = "claude"; terminal.text = screen
            let controller = Volant.HerdrResponseController(run: { try terminal.run($0) })
            let token = try XCTUnwrap(controller.read(terminal.target()).token)
            XCTAssertEqual(try controller.respond(token: token, choice: choice), "Answer sent; Claude Code resumed.")
            XCTAssertEqual(terminal.keys.last, ["enter"])
            XCTAssertEqual(terminal.keys.flatMap { $0 }.filter { $0 == "down" }.count, choice - 1)
        }
    }
    func testChangedClaudeApprovalContextPreventsInput() throws {
        let terminal = Terminal(); terminal.provider = "claude"; terminal.text = Self.claudePermission
        let controller = Volant.HerdrResponseController(run: { try terminal.run($0) })
        let token = try XCTUnwrap(controller.read(terminal.target()).token)
        terminal.text = terminal.text.replacingOccurrences(of: "Violet demo", with: "Other content")
        XCTAssertThrowsError(try controller.respond(token: token, choice: 1))
        XCTAssertTrue(terminal.keys.isEmpty)
    }

    func testSubmittedAnswerSurvivesScreenDisappearingDuringConfirmation() throws {
        let terminal = Terminal(); terminal.confirmationRace = true
        let controller = Volant.HerdrResponseController(run: { try terminal.run($0) })
        let token = try XCTUnwrap(controller.read(terminal.target()).token)
        XCTAssertEqual(try controller.respond(token: token, choice: 1), "Answer sent; Codex resumed.")
        XCTAssertEqual(terminal.keys, [["enter"]])
    }

}
