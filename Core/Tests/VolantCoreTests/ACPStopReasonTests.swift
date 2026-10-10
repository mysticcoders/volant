import XCTest

@testable import VolantCore

/// A usage limit is read from the message text, since ACP has no stop reason for it.
final class ACPStopReasonTests: XCTestCase {
    func testEachPhraseMatchesIgnoringCase() {
        for phrase in ACPStopReason.usageLimitPhrases {
            XCTAssertTrue(ACPStopReason.isUsageLimit("Fictional provider: " + phrase.uppercased() + "."), phrase)
        }
        XCTAssertTrue(ACPStopReason.isUsageLimit("Claude AI usage limit reached. Your limit resets at 3pm."))
        XCTAssertTrue(ACPStopReason.isUsageLimit("You have been rate-limited. Try again in 20 minutes."), "a hyphen reads as a space")
        XCTAssertTrue(ACPStopReason.isUsageLimit("Quota Exceeded for the fictional project"))
    }

    func testOtherStopsAndVolantsOwnLimitsAreNotUsageLimits() {
        for message in ["Ready", "Cancelled", "Stopped: max_tokens", "Stopped: refusal", "",
                        "Agent process exited. Check the provider’s terminal login and reconnect.",
                        ACPConversationLimit.refusal(),
                        "Conversation reached its display limit; connection ended.",
                        "This conversation reached its display limit. Start a new conversation.",
                        "Conversation reached its tool-detail limit.", "Conversation reached its event limit.",
                        "Agent response exceeded the ACP frame limit.", "Enter a prompt of at most 64 KB."] {
            XCTAssertFalse(ACPStopReason.isUsageLimit(message), message)
        }
    }
}
