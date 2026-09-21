import XCTest

@testable import Volant

/// The footers these agents print are UI strings that change between releases. Herdr tracks that
/// in versioned manifests it updates; Volant used to pin the exact strings, so a reworded hint
/// made a real question silently unparseable while Herdr still reported the pane blocked.
/// These cases are taken from Herdr's own rules: `live_blocked_form` in claude.toml and
/// `live_strong_blocker` in codex.toml.
final class HerdrFooterToleranceTests: XCTestCase {
    private func codex(footer: String) -> String {
        """
        Question 1/1 (1 unanswered)
        Which fictional theme should the demo use?

        › 1. Amber              warm colors
          2. Violet             cool colors
          3. None of the above  Optionally, add details in notes (tab).

        \(footer)
        """
    }

    private func claude(footer: String) -> String {
        """
        ☐ Pick a fictional colour
        Which colour should the demo use?

        ❯ 1. Amber
          2. Violet
          3. Type something.
          4. Chat about this

        \(footer)
        """
    }

    // MARK: Codex

    func testCodexAcceptsEveryVariantHerdrTreatsAsABlocker() throws {
        for footer in ["tab to add notes | enter to submit answer | esc to interrupt",
                       "enter to submit answer",
                       "enter to submit all",
                       "press enter to confirm or esc to cancel",
                       "TAB to add notes | ENTER to submit answer | ESC to interrupt"] {
            let parsed = Volant.HerdrQuestion.parse(codex(footer: footer), provider: "codex")
            XCTAssertNotNil(parsed, "footer should be recognized: \(footer)")
            XCTAssertEqual(parsed?.choices.count, 3)
            XCTAssertEqual(parsed?.selected, 1)
        }
    }

    func testCodexStillRejectsOrdinaryOutput() {
        XCTAssertNil(Volant.HerdrQuestion.parse(codex(footer: "running tests…"), provider: "codex"))
        XCTAssertNil(Volant.HerdrQuestion.parse(codex(footer: "enter to submit"), provider: "codex"),
                     "a prefix of a real hint is not one of Herdr's variants")
    }

    // MARK: Claude

    func testClaudeAcceptsEveryNavigationSpellingHerdrLists() throws {
        for hint in ["tab/arrow keys to navigate", "arrow keys to navigate", "arrows to navigate",
                     "↑/↓ to navigate", "↑↓ to navigate"] {
            let footer = "Enter to select · \(hint) · Esc to cancel"
            let parsed = Volant.HerdrQuestion.parse(claude(footer: footer), provider: "claude")
            XCTAssertNotNil(parsed, "navigation hint should be recognized: \(hint)")
            XCTAssertEqual(parsed?.selected, 1)
        }
    }

    func testClaudeAcceptsTheConfirmVariantAndIsCaseInsensitive() {
        XCTAssertNotNil(Volant.HerdrQuestion.parse(claude(footer: "Enter to confirm · Esc to cancel"), provider: "claude"))
        XCTAssertNotNil(Volant.HerdrQuestion.parse(claude(footer: "ENTER TO CONFIRM · ESC TO CANCEL"), provider: "claude"))
    }

    func testClaudeStillRequiresBothHalvesOfTheHint() {
        // Herdr's rule is "esc to cancel" AND a select or confirm hint; neither alone is a form.
        XCTAssertNil(Volant.HerdrQuestion.parse(claude(footer: "Esc to cancel"), provider: "claude"))
        XCTAssertNil(Volant.HerdrQuestion.parse(claude(footer: "Enter to select"), provider: "claude"),
                     "a select hint with no navigation hint and no cancel hint is not a form")
        XCTAssertNil(Volant.HerdrQuestion.parse(claude(footer: "Enter to select · Esc to cancel"), provider: "claude"),
                     "Herdr requires a navigation hint alongside a select hint")
    }

    func testTheFooterPredicatesThemselves() {
        XCTAssertTrue(Volant.HerdrQuestion.isClaudeApprovalFooter("Esc to cancel · Tab to amend"))
        XCTAssertFalse(Volant.HerdrQuestion.isClaudeApprovalFooter("Esc to cancel"))
        XCTAssertTrue(Volant.HerdrQuestion.isClaudeSelectFooter("Enter to confirm · Esc to cancel"))
        XCTAssertFalse(Volant.HerdrQuestion.isClaudeSelectFooter("Enter to confirm"))
        XCTAssertTrue(Volant.HerdrQuestion.isCodexFooter("enter to submit all"))
        XCTAssertFalse(Volant.HerdrQuestion.isCodexFooter("esc to interrupt"))
    }

    /// The approval path decides whether a screen is a file or command approval rather than an
    /// ordinary question, so its footer must keep matching for the safety checks below it to run.
    func testApprovalFooterIsRecognizedIndependentlyOfTheSelectFooter() {
        XCTAssertTrue(Volant.HerdrQuestion.isClaudeApprovalFooter("esc to cancel · tab to amend"))
        XCTAssertFalse(Volant.HerdrQuestion.isClaudeSelectFooter("esc to cancel · tab to amend"))
    }
}
