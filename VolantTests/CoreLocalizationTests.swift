import XCTest
import VolantCore
@testable import Volant

/// Core strings resolved through the app's `Core` table, which `swift test` doesn't have: English
/// singulars come from the catalog's plural variants, and helper codes read as messages.
final class CoreLocalizationTests: XCTestCase {
    override func setUpWithError() throws {
        try XCTSkipUnless(Bundle.main.preferredLocalizations.first == "en", "English checks need the host app running in English")
    }

    /// A count of one reads as a singular in English, which only the catalog can supply.
    func testEnglishSingularsComeFromTheCatalog() {
        let blocked = AgentSession(agent: "claude", agentStatus: "blocked", paneID: "1", terminalID: "t1")
        let herdr = HerdrStatusSummary(sessions: [blocked], connected: true, busy: false, machines: [])
        XCTAssertEqual(herdr.text, "Herdr: 1 waiting")
        XCTAssertTrue(herdr.help.hasPrefix("1 agent needs you."), herdr.help)
        XCTAssertEqual(DictationTypingSession.Outcome.typed(1).message, "Typed 1 character.")
        XCTAssertEqual(DictationTypingSession.Outcome.typed(26).message, "Typed 26 characters.")
        let english = Locale(identifier: "en_US"), now = ISO8601DateFormatter().date(from: "2026-10-06T12:15:00Z")!
        let paris = TimeZone(identifier: "Europe/Paris")!
        XCTAssertEqual(DateCalculator.evaluate("8 hours in workdays", now: now, localZone: paris, locale: english)?.result, "1 workday")
        XCTAssertEqual(DateCalculator.evaluate("workdays until tomorrow", now: now, localZone: paris, locale: english)?.result, "1 workday")
        XCTAssertEqual(ExtensionNetworkError.hostsNotApproved(["one.example", "two.example"]).errorDescription,
                       "Allow access to one.example and two.example to use this extension.")
    }

    /// A helper's code reads as its message in the app; other replies are shown unchanged.
    func testHelperCodesReadAsMessages() {
        XCTAssertEqual(HostMessage.display(HostMessage(.paneChanged).wire), "This pane or machine changed or is unavailable. Refresh before continuing.")
        XCTAssertEqual(HostMessage.display(AIHTTPError.wire(AIHTTPError.http(502))), "The AI server returned HTTP 502. Check your connection settings.")
        XCTAssertEqual(HostMessage.display("Provider said no."), "Provider said no.")
    }
}
