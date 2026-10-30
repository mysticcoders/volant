import XCTest
@testable import VolantCore

final class HostMessageTests: XCTestCase {
    /// Every code survives the trip through a reply string, with and without an argument.
    func testEveryCodeRoundTrips() {
        for code in HostMessage.Code.allCases {
            XCTAssertEqual(HostMessage(wire: HostMessage(code).wire), HostMessage(code))
            XCTAssertEqual(HostMessage(wire: HostMessage(code, "Claude Code").wire), HostMessage(code, "Claude Code"))
            XCTAssertFalse(HostMessage(code).text.isEmpty)
        }
    }

    /// A code is shown as its message; an agent's or provider's own text, or an unknown code, is
    /// shown as it arrived.
    func testDisplayMapsCodesAndKeepsOtherText() {
        XCTAssertEqual(HostMessage.display(HostMessage(.rexNotRunning).wire), "Rex isn’t running. Open Rex, then try again.")
        XCTAssertEqual(HostMessage.display(HostMessage(.answerSentResumed, "Codex").wire), "Answer sent; Codex resumed.")
        XCTAssertEqual(HostMessage.display(HostMessage(.aiHTTPStatus, "503").wire), "The AI server returned HTTP 503. Check your connection settings.")
        XCTAssertEqual(HostMessage.display("Session not found."), "Session not found.")
        XCTAssertEqual(HostMessage.display(HostMessage.prefix + "no-such-code"), HostMessage.prefix + "no-such-code")
        XCTAssertNil(HostMessage.display(nil as String?))
    }

    /// A helper replies with the code of a known error and with the description of any other.
    func testHelperRepliesForErrors() {
        XCTAssertEqual(HostMessage.wire(for: HostMessage(.paneChanged)), HostMessage(.paneChanged).wire)
        XCTAssertEqual(HostMessage.wire(for: FSearchError.timedOut), HostMessage(.fsearchTimedOut).wire)
        XCTAssertEqual(HostMessage.wire(for: FSearchError.daemon("index busy")), "fsearch: index busy")
        XCTAssertEqual(HostMessage.wire(for: AIHTTPError.http(429)), HostMessage(.aiRateLimited).wire)
        XCTAssertEqual(HostMessage.wire(for: HostMessage(.savedMachineChanged).error(domain: "VolantHerdrResponse", code: 2)), HostMessage(.savedMachineChanged).wire)
        let other = NSError(domain: "VolantACP", code: 1, userInfo: [NSLocalizedDescriptionKey: "The agent stopped."])
        XCTAssertEqual(HostMessage.wire(for: other), "The agent stopped.")
        XCTAssertEqual(AIHTTPError.wire(URLError(.cannotConnectToHost)), HostMessage(.aiUnreachable).wire)
    }

    /// An error built for helper code keeps its domain and describes itself in words.
    func testErrorKeepsDomainAndDescription() {
        let error = HostMessage(.savedMachineRemoved).error(domain: "VolantHerdrResponse", code: 3)
        XCTAssertEqual(error.domain, "VolantHerdrResponse")
        XCTAssertEqual(error.code, 3)
        XCTAssertEqual(error.localizedDescription, "This saved machine changed or was removed. Refresh before continuing.")
    }
}
