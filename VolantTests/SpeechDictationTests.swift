import XCTest
import VolantCore

@testable import Volant

/// Dictation needs macOS 26 and a microphone grant. These assertions hold either way: on an older
/// system the feature must be absent with a reason, never broken.
@MainActor
final class SpeechDictationTests: XCTestCase {
    func testAvailabilityAlwaysExplainsItselfWhenUnavailable() {
        let availability = SpeechDictation.availability
        if availability.isReady {
            XCTAssertNil(availability.reason)
        } else {
            XCTAssertFalse((availability.reason ?? "").isEmpty, "a refusal has to say what to do about it")
        }
    }

    func testOlderSystemsNameTheRequirement() {
        guard #unavailable(macOS 26.0) else { return }
        let reason = SpeechDictation.availability.reason ?? ""
        XCTAssertTrue(reason.contains("macOS"))
        XCTAssertFalse(SpeechDictation.availability.isReady)
    }

    func testANewSessionIsIdleAndEmpty() {
        let dictation = SpeechDictation()
        XCTAssertEqual(dictation.phase, .idle)
        XCTAssertTrue(dictation.transcript.isEmpty)
        XCTAssertFalse(dictation.isListening)
    }

    func testCancelIsSafeWhenNothingIsRunning() {
        let dictation = SpeechDictation()
        dictation.cancel()
        dictation.cancel()
        XCTAssertEqual(dictation.phase, .idle)
    }

    func testStoppingWhenNotListeningReportsNothing() {
        let stopped = expectation(description: "stopped")
        SpeechDictation().stop { transcript in
            XCTAssertNil(transcript)
            stopped.fulfill()
        }
        wait(for: [stopped], timeout: 2)
    }

    func testAnUnavailableSystemFailsWithAReasonRatherThanHanging() {
        guard !SpeechDictation.availability.isReady else { return }
        let dictation = SpeechDictation()
        let finished = expectation(description: "finished")
        dictation.start { transcript in
            XCTAssertNil(transcript)
            finished.fulfill()
        }
        wait(for: [finished], timeout: 3)
        guard case .failed(let reason) = dictation.phase else {
            return XCTFail("an unavailable system must land in failed")
        }
        XCTAssertFalse(reason.isEmpty)
    }
}
