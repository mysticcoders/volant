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

    func testAFailedSaveLeavesTheChoiceAsItWas() {
        let model = RexOverviewModel(previewsAllowed: false, save: { _ in throw CocoaError(.fileWriteNoPermission) })
        model.allowPreviews(true)
        XCTAssertFalse(model.previewsAllowed)
        XCTAssertNotNil(model.feedback)
    }
}
