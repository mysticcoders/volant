import XCTest

@testable import Volant

/// Codex asks two different kinds of question. The numbered survey form was already handled; this
/// covers the approval form, which has no "Question 1/1" header and a single column of options.
/// Shape taken from a real screen, content fictional.
final class HerdrCodexApprovalTests: XCTestCase {
    private static let approval = """
      • Running sed -n '1,20p' fictional/Demo.swift

        Would you like to run the following command?

        Environment: local

        Reason: Inspect the fictional demo view.

        $ sed -n '1,20p' fictional/Demo.swift

      › 1. Yes, proceed (y)
        2. Yes, and don't ask again for commands that start with `sed -n '1,20p' fictional/
           Demo.swift` (p)
        3. No, and tell Codex what to do differently (esc)

        Press enter to confirm or esc to cancel
    """

    func testAnApprovalScreenIsParsedIntoAnswerableChoices() throws {
        let parsed = try XCTUnwrap(Volant.HerdrQuestion.parse(Self.approval, provider: "codex"))
        XCTAssertEqual(parsed.title, "Would you like to run the following command?")
        XCTAssertEqual(parsed.progress, "Codex approval")
        XCTAssertEqual(parsed.selected, 1)
        XCTAssertEqual(parsed.choices.count, 3)
        XCTAssertEqual(parsed.choices.first?.label, "Yes, proceed (y)")
        XCTAssertEqual(parsed.choices.last?.label, "No, and tell Codex what to do differently (esc)")
        XCTAssertEqual(parsed.answerChoices.count, 3, "every option on an approval screen is answerable")
    }

    func testAWrappedOptionKeepsItsWholeLabel() throws {
        let parsed = try XCTUnwrap(Volant.HerdrQuestion.parse(Self.approval, provider: "codex"))
        let wrapped = try XCTUnwrap(parsed.choices.first { $0.number == 2 })
        XCTAssertTrue(wrapped.label.contains("don't ask again"))
        XCTAssertTrue(wrapped.label.hasSuffix("Demo.swift` (p)"), "the continuation line is joined")
    }

    func testTheCommandBlockIsCarriedAsContext() throws {
        let parsed = try XCTUnwrap(Volant.HerdrQuestion.parse(Self.approval, provider: "codex"))
        let context = try XCTUnwrap(parsed.context)
        XCTAssertTrue(context.contains("$ sed -n '1,20p' fictional/Demo.swift"))
        XCTAssertTrue(context.contains("Reason: Inspect the fictional demo view."))
    }

    func testAClippedCommandIsRefusedRatherThanApprovedBlind() {
        let clipped = Self.approval.replacingOccurrences(
            of: "$ sed -n '1,20p' fictional/Demo.swift",
            with: "$ sed -n '1,20p' fictional/Demo.swift …")
        XCTAssertNil(Volant.HerdrQuestion.parse(clipped, provider: "codex"),
                     "a partly shown command must never get a one-key approval")
    }

    func testTwoSelectionMarkersAreRefused() {
        let ambiguous = Self.approval.replacingOccurrences(of: "  2. Yes, and", with: "› 2. Yes, and")
        XCTAssertNil(Volant.HerdrQuestion.parse(ambiguous, provider: "codex"))
    }

    func testAnUnrecognizedPromptIsRefused() {
        let unknown = Self.approval.replacingOccurrences(
            of: "Would you like to run the following command?", with: "Something unfamiliar happened.")
        XCTAssertNil(Volant.HerdrQuestion.parse(unknown, provider: "codex"))
    }

    func testANonBlockingScreenIsStillIgnored() {
        let running = Self.approval.replacingOccurrences(
            of: "Press enter to confirm or esc to cancel", with: "running tests…")
        XCTAssertNil(Volant.HerdrQuestion.parse(running, provider: "codex"))
    }

    func testTheNumberedSurveyFormStillParses() throws {
        let survey = """
          Question 1/1 (1 unanswered)
          Which fictional theme should the demo use?

          › 1. Amber              warm colors
            2. None of the above  Optionally, add details in notes (tab).

          tab to add notes | enter to submit answer | esc to interrupt
        """
        let parsed = try XCTUnwrap(Volant.HerdrQuestion.parse(survey, provider: "codex"))
        XCTAssertEqual(parsed.progress, "Question 1/1 (1 unanswered)")
        XCTAssertEqual(parsed.choices.count, 2)
    }

    func testClaudeScreensAreUnaffectedByTheCodexApprovalPath() {
        XCTAssertNil(Volant.HerdrQuestion.parse(Self.approval, provider: "claude"))
    }
}
