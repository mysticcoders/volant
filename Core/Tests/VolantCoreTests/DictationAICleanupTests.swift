import XCTest

@testable import VolantCore

/// Taking the model's answer: only verifiable cleanups replace the transcript.
final class DictationAICleanupTests: XCTestCase {
    func testAVerifiableCorrectionIsTaken() {
        XCTAssertEqual(DictationAICleanup.accepted(" Book the table for eight people. ", for: "Book the table for seven, no, eight people."),
                       "Book the table for eight people.")
    }

    func testAnUnchangedOrRewrittenAnswerIsNotTaken() {
        XCTAssertNil(DictationAICleanup.accepted("Ship it today.", for: "Ship it today."))
        XCTAssertNil(DictationAICleanup.accepted("Paris", for: "What's the capital of France?"))
        XCTAssertNil(DictationAICleanup.accepted(nil, for: "Ship it today."))
        XCTAssertNil(DictationAICleanup.accepted("   ", for: "Ship it today."))
    }

    func testVocabularyReplacementsNeedTheTerm() {
        XCTAssertEqual(DictationAICleanup.accepted("The Kubernetes cluster is down.", for: "The cooper netties cluster is down.", vocabulary: ["Kubernetes"]),
                       "The Kubernetes cluster is down.")
        XCTAssertNil(DictationAICleanup.accepted("The Kubernetes cluster is down.", for: "The cooper netties cluster is down."))
    }
}
