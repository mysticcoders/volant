import XCTest
@testable import VolantCore

final class HerdrStatusSummaryTests: XCTestCase {
    private func pane(_ status: String, _ id: String) -> AgentSession {
        AgentSession(agent: "claude", agentStatus: status, paneID: id, terminalID: "t" + id)
    }
    private let studio = HerdrMachineStatus(id: "remote:studio", label: "Studio", state: "unavailable", detail: "Connection timed out")
    private let lab = HerdrMachineStatus(id: "remote:lab", label: "Lab", state: "unavailable", detail: "Host unreachable")

    func testBlockedPanesCountAsWaiting() {
        let summary = HerdrStatusSummary(sessions: [pane("blocked", "1"), pane("blocked", "2"), pane("blocked", "3"), pane("working", "4"), pane("done", "5")],
                                         connected: true, busy: false, machines: [])
        XCTAssertEqual(summary.text, "Herdr: 3 waiting")
        XCTAssertEqual(summary.tone, .waiting)
        XCTAssertTrue(summary.help.hasPrefix("3 agents need you."))
    }

    func testWaitingOutranksAnUnavailableMachine() {
        let summary = HerdrStatusSummary(sessions: [pane("blocked", "1")], connected: true, busy: false, machines: [studio])
        XCTAssertEqual(summary.text, "Herdr: 1 waiting")
        XCTAssertTrue(summary.help.contains("Studio: Connection timed out"))
    }

    func testUnavailableMachinesWhenNothingWaits() {
        XCTAssertEqual(HerdrStatusSummary(sessions: [pane("working", "1")], connected: true, busy: false, machines: [studio]).text, "Herdr: Studio unavailable")
        let two = HerdrStatusSummary(sessions: [], connected: true, busy: true, machines: [studio, lab])
        XCTAssertEqual(two.text, "Herdr: 2 machines unavailable")
        XCTAssertEqual(two.tone, .warning)
    }

    func testLoadingOnlyUntilPanesArrive() {
        XCTAssertEqual(HerdrStatusSummary(sessions: [], connected: true, busy: true, machines: []).text, "Herdr: loading…")
        XCTAssertEqual(HerdrStatusSummary(sessions: [pane("idle", "1")], connected: true, busy: true, machines: []).text, "Herdr: none waiting")
    }

    /// The footer's orange keeps its hue in dark themes and darkens only as far as AA needs on a
    /// light background, for the system colors and every palette.
    func testWarningColorIsReadableInEveryTheme() {
        XCTAssertEqual(ColorPalette.readable("#ff9f0a", on: "#1e1e1e", toward: "#ffffff"), "#ff9f0a")
        let light = ColorPalette.readable("#ff9500", on: "#ececec", toward: "#000000")
        XCTAssertNotEqual(light, "#ff9500")
        XCTAssertGreaterThanOrEqual(ColorPalette.contrast(light, "#ececec") ?? 0, 4.5)
        for theme in ColorTheme.catalog {
            guard let palette = theme.palette else { continue }
            let color = ColorPalette.readable(palette.orange, on: palette.background, toward: palette.text)
            XCTAssertGreaterThanOrEqual(ColorPalette.contrast(color, palette.background) ?? 0, 4.5, theme.id)
        }
    }

    func testQuietAndDisconnectedStates() {
        let quiet = HerdrStatusSummary(sessions: [pane("working", "1"), pane("idle", "2")], connected: true, busy: false, machines: [], unread: 1)
        XCTAssertEqual(quiet.text, "Herdr: none waiting")
        XCTAssertEqual(quiet.tone, .quiet)
        XCTAssertTrue(quiet.help.contains("1 changed since you last looked"))
        XCTAssertEqual(HerdrStatusSummary(sessions: [pane("blocked", "1")], connected: false, busy: false, machines: []).text, "Herdr: not connected")
    }
}
