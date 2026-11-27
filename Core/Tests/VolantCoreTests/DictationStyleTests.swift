import Foundation
import XCTest

@testable import VolantCore

/// Dictation styles rearrange a transcript without changing its words: sentence splitting, the
/// message period, note bullets, and email greetings, paragraphs and sign-offs.
final class DictationStyleTests: XCTestCase {
    private let english = Locale(identifier: "en_US")
    private let french = Locale(identifier: "fr_FR")

    func testSentencesSplitAfterEndsFollowedBySpace() {
        XCTAssertEqual(DictationStyle.sentences(in: "One. Two! Three? Four"), ["One.", "Two!", "Three?", "Four"])
        XCTAssertEqual(DictationStyle.sentences(in: "It costs 3.50 today. Ok."), ["It costs 3.50 today.", "Ok."])
        XCTAssertEqual(DictationStyle.sentences(in: "He said \"go.\" Then left."), ["He said \"go.\"", "Then left."])
        XCTAssertEqual(DictationStyle.sentences(in: "Wait... what?"), ["Wait...", "what?"])
        XCTAssertEqual(DictationStyle.sentences(in: "  "), [])
    }

    func testPlainOnlyTrims() {
        XCTAssertEqual(DictationStyle.plain.format("  Hi there. Bye.  ", locale: english), "Hi there. Bye.")
        XCTAssertEqual(DictationStyle.plain.format("   ", locale: english), "")
    }

    func testMessageDropsOnlyASingleClosingPeriod() {
        XCTAssertEqual(DictationStyle.message.format("On my way. Be there soon.", locale: english), "On my way. Be there soon")
        XCTAssertEqual(DictationStyle.message.format("Are you coming?", locale: english), "Are you coming?")
        XCTAssertEqual(DictationStyle.message.format("Well...", locale: english), "Well...")
    }

    func testNotesBulletEachSentence() {
        XCTAssertEqual(DictationStyle.notes.format("Buy milk. Call the bank? Ship it!", locale: english),
                       "- Buy milk\n- Call the bank?\n- Ship it!")
        XCTAssertEqual(DictationStyle.notes.format("Just one", locale: english), "- Just one")
    }

    func testEmailPutsGreetingParagraphsAndSignOffOnTheirOwnLines() {
        let spoken = "Hi Sam, I looked at the draft. It reads well. The numbers match. One question on the budget. Can we talk Friday? Thanks, Andrew."
        XCTAssertEqual(DictationStyle.email.format(spoken, locale: english), """
            Hi Sam,

            I looked at the draft. It reads well. The numbers match.

            One question on the budget. Can we talk Friday?

            Thanks,
            Andrew
            """)
    }

    func testEmailKeepsASignOffWithoutANameAsItsOwnParagraph() {
        XCTAssertEqual(DictationStyle.email.format("Hello. the file is attached. Thanks so much!", locale: english),
                       "Hello,\n\nThe file is attached.\n\nThanks so much!")
    }

    func testEmailWithoutGreetingOrSignOffIsParagraphsOnly() {
        XCTAssertEqual(DictationStyle.email.format("The meeting moved. It is at three now.", locale: english),
                       "The meeting moved. It is at three now.")
    }

    func testEmailRecognizesGreetingsOnlyInEnglish() {
        XCTAssertEqual(DictationStyle.email.format("Hi Sam, the file is here. Thanks, Léa.", locale: french),
                       "Hi Sam, the file is here. Thanks, Léa.")
    }

    func testTextWithLinesKeepsThem() {
        let list = "Groceries:\n1. Eggs\n2. Milk."
        XCTAssertEqual(DictationStyle.notes.format(list, locale: english), list)
        XCTAssertEqual(DictationStyle.email.format(list, locale: english), list)
        XCTAssertEqual(DictationStyle.message.format(list, locale: english), "Groceries:\n1. Eggs\n2. Milk")
    }

    func testAWordThatOnlyStartsLikeAGreetingIsNotOne() {
        XCTAssertEqual(DictationStyle.email.format("Hither and yon we went.", locale: english), "Hither and yon we went.")
        XCTAssertEqual(DictationStyle.email.format("We went. Bestow it on them.", locale: english), "We went. Bestow it on them.")
    }
}
