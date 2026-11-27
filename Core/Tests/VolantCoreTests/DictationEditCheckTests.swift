import XCTest

@testable import VolantCore

/// The strict edit check on model cleanups, with the cleanups Apple's on-device model returned
/// when measured on macOS 27: the ones that resolved a spoken correction pass, and the ones that
/// changed a day, kept the taken-back words or rewrote the request fail.
final class DictationEditCheckTests: XCTestCase {
    private func check(_ original: String, _ cleaned: String, vocabulary: [String] = []) -> Bool {
        DictationEditCheck.isAcceptable(original: original, cleaned: cleaned, vocabulary: vocabulary)
    }

    func testSelfCorrectionsEndingInACuePass() {
        XCTAssertTrue(check("we should use cloud code on tuesday, no wait, wednesday", "we should use cloud code on wednesday"))
        XCTAssertTrue(check("Remind me to call mom, actually, call dad at 6.", "Remind me to call dad at 6."))
        XCTAssertTrue(check("We need three more chairs, scratch that, four more chairs.", "We need four more chairs."))
        XCTAssertTrue(check("Review it before lunch, no, before end of day.", "Review it before end of day."))
    }

    func testKeepingTheTakenBackWordsFails() {
        XCTAssertFalse(check("Let's meet at the coffee shop, I mean the bakery, on Main Street.", "Let's meet at the coffee shop on Main Street."))
    }

    func testSwappedWordsFail() {
        XCTAssertFalse(check("Can you send me the report by Friday?", "Can you send me the report by wednesday?"))
        XCTAssertFalse(check("Tell Sarah the deadline moved to March.", "Tell Sarah the deadline moved to wednesday."))
        XCTAssertFalse(check("Should we push the launch to next week?", "Should we push the launch to wednesday?"))
    }

    func testAnswersAndAddedWordsFail() {
        XCTAssertFalse(check("What's the capital of France?", "Paris"))
        XCTAssertFalse(check("I don't think we should ship it today.", "I think we should ship it today."))
        XCTAssertFalse(check("Call me later.", "Sure! Call me later."))
    }

    func testCaseAndPunctuationAreFree() {
        XCTAssertTrue(check("the flight leaves monday morning from boston", "The flight leaves Monday morning from Boston."))
        XCTAssertTrue(check("I'll be there", "I’ll be there."))
    }

    func testFillersAndRepeatsMayGo() {
        XCTAssertTrue(check("so um the build is uh green", "so the build is green"))
        XCTAssertTrue(check("I I think the the tests pass", "I think the tests pass"))
    }

    func testVocabularyTermsMayReplaceMisheardWords() {
        XCTAssertTrue(check("the cooper netties cluster is down", "the Kubernetes cluster is down", vocabulary: ["Kubernetes"]))
        XCTAssertFalse(check("the cooper netties cluster is down", "the Kubernetes cluster is down"))
    }

    func testACueWithNothingAfterItIsNoCorrection() {
        XCTAssertFalse(check("Send it to Sam, actually", "Send it"))
    }

    func testAWordCueCountsOnlyWhenSetOff() {
        XCTAssertFalse(check("There is no way we ship today.", "way we ship today."))
        XCTAssertTrue(check("Ship it Tuesday, no, Wednesday.", "Ship it Wednesday."))
    }

    func testACorrectionStaysInItsSentence() {
        XCTAssertFalse(check("We left early. Then, actually, we came back.", "Then we came back."))
        XCTAssertTrue(check("We left early. Then, actually, we came back.", "We left early. We came back."))
    }
}
