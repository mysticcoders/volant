import AppKit
import XCTest
import VolantCore
@testable import Volant

/// The overview reads Rex, and so screen text, only while its window is open with pane previews
/// turned on, and forgets everything when either stops. An injected reader stands in for the helper.
@MainActor
final class RexOverviewModelTests: XCTestCase {
    typealias Reply = (Data?, Int, String?) -> Void
    private func drain() async { await withCheckedContinuation { continuation in DispatchQueue.main.async { continuation.resume() } } }
    private let overview = RexOverview(sessions: [.init(sessionID: "session:a", label: "orbit", tabs: [
        .init(windowID: "window:w", label: "api", panes: [.init(blockID: "block:b", label: "shell", rect: [0, 0, 1, 1], preview: ["fictional screen text"])])
    ])])

    func testReadsOnlyWithTheWindowOpenAndPreviewsAllowed() async throws {
        var saved: [Bool] = []
        let model = RexOverviewModel(previewsAllowed: false, save: { saved.append($0) })
        var reads: [Bool] = [], reply: Reply?
        model.reader = { _, preview, next in reads.append(preview); reply = next }
        model.windowOpened()
        XCTAssertTrue(reads.isEmpty, "an open window without previews reads nothing")
        model.allowPreviews(true)
        XCTAssertEqual(saved, [true])
        XCTAssertEqual(reads, [true], "approving inline starts reading, with previews")
        reply?(try JSONEncoder().encode(overview), 1, nil)
        await drain()
        XCTAssertEqual(model.overview.sessions.first?.tabs.first?.panes.first?.preview, ["fictional screen text"])
        model.updateAllowed(false)
        XCTAssertTrue(model.overview.sessions.isEmpty, "turning previews off in Settings forgets the screen text at once")
        reply?(try JSONEncoder().encode(overview), 2, nil)
        await drain()
        XCTAssertTrue(model.overview.sessions.isEmpty, "a reply after turning previews off is dropped")
        model.updateAllowed(true)
        XCTAssertEqual(reads.count, 3, "turning previews back on in Settings reads again while the window is open")
        model.windowClosed()
        XCTAssertTrue(model.overview.sessions.isEmpty, "closing forgets everything read")
    }

    func testAllowingWithTheWindowClosedReadsNothingUntilItOpens() {
        let model = RexOverviewModel(previewsAllowed: false)
        var reads = 0
        model.reader = { _, _, _ in reads += 1 }
        model.updateAllowed(true)
        XCTAssertEqual(reads, 0)
        model.windowOpened()
        XCTAssertEqual(reads, 1)
        model.windowClosed()
    }

    private func key(_ code: UInt16, _ characters: String, _ modifiers: NSEvent.ModifierFlags = []) -> NSEvent {
        NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: modifiers, timestamp: 0, windowNumber: 0, context: nil,
                         characters: characters, charactersIgnoringModifiers: characters, isARepeat: false, keyCode: code)!
    }

    private var grid: RexOverview {
        RexOverview(sessions: [
            .init(sessionID: "session:orbit", label: "orbit", tabs: [
                .init(windowID: "window:api", label: "api", panes: [
                    .init(blockID: "block:agent", label: "shell", rect: [0, 0, 0.5, 1]),
                    .init(blockID: "block:logs", label: "logs", rect: [0.5, 0, 0.5, 1]),
                ]),
            ]),
            .init(sessionID: "session:ops", label: "ops", tabs: [
                .init(windowID: "window:deploy", label: "deploy", panes: [.init(blockID: "block:deploy", label: "shell", status: RexStatus(state: .blocked), rect: [0, 0, 1, 1])]),
            ]),
        ])
    }

    func testKeysMoveTheSelectionAndReturnFocusesIt() {
        let model = RexOverviewModel(previewsAllowed: true)
        var focused: [String] = [], closes = 0
        model.focuser = { session, block, done in focused.append(session + "/" + block); done(nil) }
        model.activateRex = {}
        model.show(grid)
        let handle = { (event: NSEvent) in RexOverviewWindowController.handle(event, model: model, close: { closes += 1 }) }
        XCTAssertEqual(model.selection?.blockID, "block:deploy", "selection starts on the waiting pane")
        XCTAssertTrue(handle(key(123, "\u{F702}")))
        XCTAssertEqual(model.selection?.blockID, "block:agent", "left moves to the previous tab, at its first pane")
        XCTAssertTrue(handle(key(125, "\u{F701}")))
        XCTAssertEqual(model.selection?.blockID, "block:logs", "down moves to the next pane in the tab")
        XCTAssertTrue(handle(key(48, "\t")))
        XCTAssertEqual(model.selection?.blockID, "block:deploy", "Tab jumps to the next waiting pane")
        XCTAssertTrue(handle(key(48, "\t", .shift)))
        XCTAssertEqual(model.selection?.blockID, "block:deploy", "Shift-Tab with one waiting pane stays")
        XCTAssertTrue(handle(key(36, "\r")))
        XCTAssertEqual(focused, ["session:ops/block:deploy"], "Return focuses the selected pane by identity")
        XCTAssertFalse(handle(key(13, "w", .command)), "Command-W and other shortcuts pass through")
        XCTAssertFalse(handle(key(124, "\u{F703}", .option)))
        XCTAssertTrue(handle(key(53, "\u{1B}")))
        XCTAssertEqual(closes, 1, "Escape closes the overview")
    }

    func testTheApprovalCardKeepsReturnForItsButton() {
        let model = RexOverviewModel(previewsAllowed: false)
        var closes = 0
        model.show(grid)
        XCTAssertFalse(model.keyboardActive)
        XCTAssertFalse(RexOverviewWindowController.handle(key(36, "\r"), model: model, close: { closes += 1 }), "Return reaches Turn On Pane Previews")
        XCTAssertFalse(RexOverviewWindowController.handle(key(125, "\u{F701}"), model: model, close: { closes += 1 }))
        XCTAssertTrue(RexOverviewWindowController.handle(key(53, "\u{1B}"), model: model, close: { closes += 1 }))
        XCTAssertEqual(closes, 1)
    }

    func testSelectionFollowsThePaneThroughRefreshes() {
        let model = RexOverviewModel(previewsAllowed: true)
        model.show(grid)
        model.select(.init(sessionID: "session:orbit", blockID: "block:logs"))
        let reordered = RexOverview(sessions: [grid.sessions[1], grid.sessions[0]])
        model.show(reordered)
        XCTAssertEqual(model.selection, .init(sessionID: "session:orbit", blockID: "block:logs"), "reordering keeps the same pane")
        model.show(RexOverview(sessions: [grid.sessions[1]]))
        XCTAssertEqual(model.selection?.blockID, "block:deploy", "a closed session hands selection to the start")
        model.select(.init(sessionID: "session:gone", blockID: "block:nothing"))
        XCTAssertEqual(model.selection?.blockID, "block:deploy", "a pane the overview doesn't show can't be selected")
    }

    func testAFailedSaveLeavesTheChoiceAsItWas() {
        let model = RexOverviewModel(previewsAllowed: false, save: { _ in throw CocoaError(.fileWriteNoPermission) })
        model.allowPreviews(true)
        XCTAssertFalse(model.previewsAllowed)
        XCTAssertNotNil(model.feedback)
    }
}
