import XCTest

@testable import VolantCore

/// A stored session ID came from an agent, so it is checked again before it is sent back.
final class ACPResumeRecordTests: XCTestCase {
    func testAcceptsTheSessionIDShapesProvidersReturn() {
        XCTAssertTrue(ACPResumeRecord.isValidSessionID("0b7c3f9e-5d1a-4c2e-9f61-1f2a3b4c5d6e"))
        XCTAssertTrue(ACPResumeRecord.isValidSessionID("ses_fictional01AbC"))
    }

    func testRejectsEmptyOversizedAndUnprintableIDs() {
        XCTAssertFalse(ACPResumeRecord.isValidSessionID(""))
        XCTAssertFalse(ACPResumeRecord.isValidSessionID(String(repeating: "a", count: 257)))
        XCTAssertTrue(ACPResumeRecord.isValidSessionID(String(repeating: "a", count: 256)))
        for bad in ["has space", "line\nbreak", "nul\u{0}", "../escape", "back\\slash", "caf\u{E9}"] {
            XCTAssertFalse(ACPResumeRecord.isValidSessionID(bad), bad)
        }
    }

    func testRecordNeedsAKnownProviderAndMatchesOnlyItsOwnFolder() {
        let record = ACPResumeRecord(provider: "claude", project: "/tmp/fictional-project", sessionID: "fictional-session")
        XCTAssertTrue(record.isValid)
        XCTAssertTrue(record.matches(provider: "claude", project: "/tmp/fictional-project"))
        XCTAssertFalse(record.matches(provider: "codex", project: "/tmp/fictional-project"))
        XCTAssertFalse(record.matches(provider: "claude", project: ""))
        XCTAssertFalse(ACPResumeRecord(provider: "unknown", project: "", sessionID: "fictional-session").isValid)
        XCTAssertFalse(ACPResumeRecord(provider: "claude", project: "", sessionID: "bad id").isValid)
    }

    func testRecordRoundTripsThroughJSON() throws {
        let record = ACPResumeRecord(provider: "codex", project: "", sessionID: "fictional-session", savedAt: Date(timeIntervalSince1970: 1_800_000_000))
        XCTAssertEqual(try JSONDecoder().decode(ACPResumeRecord.self, from: JSONEncoder().encode(record)), record)
    }

    func testLoadSessionCapabilityIsReadOnlyWhenAdvertised() {
        XCTAssertTrue(ACPCapabilities.supportsLoadSession(#"{"loadSession":true}"#))
        XCTAssertFalse(ACPCapabilities.supportsLoadSession(#"{"loadSession":false}"#))
        XCTAssertFalse(ACPCapabilities.supportsLoadSession(#"{"promptCapabilities":{"embeddedContext":true}}"#))
        XCTAssertFalse(ACPCapabilities.supportsLoadSession("{}"))
        XCTAssertFalse(ACPCapabilities.supportsLoadSession("not json"))
    }
}
