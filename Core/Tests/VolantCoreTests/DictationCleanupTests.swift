import Foundation
import XCTest

@testable import VolantCore

/// Filler removal on dictated phrases: what is removed, what is kept, and how commas, spacing and
/// sentence capitals are repaired.
final class DictationCleanupTests: XCTestCase {
    private let english = Locale(identifier: "en_US")
    private func clean(_ text: String) -> String { DictationCleanup.removingFillers(text, locale: english) }

    func testFillersAreRemovedAndTheSentenceRepaired() {
        XCTAssertEqual(clean("Um, so we should ship it."), "So we should ship it.")
        XCTAssertEqual(clean("So, um, we should ship it."), "So, we should ship it.")
        XCTAssertEqual(clean("I um think uh it works."), "I think it works.")
        XCTAssertEqual(clean("And then, uh we left."), "And then we left.")
        XCTAssertEqual(clean("It was fine um."), "It was fine.")
        XCTAssertEqual(clean("Hmm. Let me check. Uhh, yes."), "Let me check. Yes.")
        XCTAssertEqual(clean("Umm I mean, erm, it's like that."), "I mean, it's like that.")
        XCTAssertEqual(clean("We shipped it. Uh, then it broke."), "We shipped it. Then it broke.")
        XCTAssertEqual(clean("Let me check. Hmm. Yes."), "Let me check. Yes.")
        XCTAssertEqual(clean("Wait... um what?"), "Wait... what?")
    }

    func testPhrasesKeepTheirLeadingSpaceAndFillerOnlyPhrasesVanish() {
        XCTAssertEqual(clean(" um, and then we left."), " and then we left.")
        XCTAssertEqual(clean(" Um."), "")
        XCTAssertEqual(clean("uh"), "")
        XCTAssertEqual(clean(" Uh, um,"), "")
    }

    func testWordsThatCarryMeaningStay() {
        for text in ["Uh-oh, that broke.", "She said uh-huh.", "Mhm, that works.", "To err is human.", "Go to the ER now.",
                     "UM won the game.", "The umbrella is under the hum of the fan.", "It's like, you know, fine.", "Herman and Erma came.",
                     "Ah, I see."] {
            XCTAssertEqual(clean(text), text, text)
        }
    }

    func testOnlyEnglishIsCleaned() {
        XCTAssertEqual(DictationCleanup.removingFillers("Euh, um, oui.", locale: Locale(identifier: "fr_FR")), "Euh, um, oui.")
        XCTAssertTrue(DictationCleanup.supports(Locale(identifier: "en_GB")))
        XCTAssertFalse(DictationCleanup.supports(Locale(identifier: "de_DE")))
    }
}
