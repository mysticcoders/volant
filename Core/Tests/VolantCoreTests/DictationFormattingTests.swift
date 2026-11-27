import Foundation
import XCTest

@testable import VolantCore

/// Volant's entry point to spoken formatting: phrases keep how the recognizer spaced them,
/// vocabulary terms stay in words, and lists are formed only on a whole transcript. A
/// punctuation name the recognizer put at the very start of a phrase has no word to attach to,
/// so it stays as said.
final class DictationFormattingTests: XCTestCase {
    private let english = Locale(identifier: "en_US")

    func testPhrasesGetDigitsAndMarksAndKeepTheirLeadingSpace() {
        XCTAssertEqual(DictationFormatting.formattingPhrase(" It took twenty five minutes.", locale: english), " It took 25 minutes.")
        XCTAssertEqual(DictationFormatting.formattingPhrase("See you at noon comma bring snacks", locale: english), "See you at noon, bring snacks")
        XCTAssertEqual(DictationFormatting.formattingPhrase("   ", locale: english), "   ")
    }

    func testANameAloneAtAPhraseStartStaysAsSaid() {
        XCTAssertEqual(DictationFormatting.formattingPhrase(" question mark", locale: english), " question mark")
    }

    func testVocabularyTermsStayInWords() {
        XCTAssertEqual(DictationFormatting.formattingPhrase("Lunch at five guys for twenty bucks", locale: english, protectedTerms: ["Five Guys"]),
                       "Lunch at five guys for 20 bucks")
    }

    func testListsFormOnlyOnTheWholeTranscript() {
        let spoken = "Groceries: first, eggs. Second, milk. Third, bread."
        XCTAssertEqual(DictationFormatting.formattingPhrase(spoken, locale: english), spoken)
        XCTAssertEqual(DictationFormatting.formattingTranscript(spoken, locale: english), "Groceries:\n1. Eggs\n2. Milk\n3. Bread")
    }

    func testATakenBackNumberMatchesItsCorrection() {
        XCTAssertEqual(DictationFormatting.formattingPhrase("Book the table for seven, no, eight people.", locale: english),
                       "Book the table for 7, no, 8 people.")
        XCTAssertEqual(DictationFormatting.formattingPhrase("It costs twenty five, sorry, thirty dollars", locale: english),
                       "It costs 25, sorry, $30")
        XCTAssertEqual(DictationFormatting.formattingPhrase("I said no to eight people", locale: english), "I said no to 8 people")
        XCTAssertEqual(DictationFormatting.formattingPhrase("Tell him no, 8 is fine", locale: english), "Tell him no, 8 is fine")
    }
}
