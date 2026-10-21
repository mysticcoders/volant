import XCTest
import VolantCore
@testable import Volant

/// The overview never shows or keeps screen text unless the owner allowed previews and is in
/// Preview mode. An injected reader stands in for the helper.
@MainActor
final class RexOverviewModelTests: XCTestCase {
    typealias Reply = (Data?, Int, String?) -> Void
    private func drain() async { await withCheckedContinuation { continuation in DispatchQueue.main.async { continuation.resume() } } }
    private let overview = RexOverview(sessions: [.init(sessionID: "session:a", label: "orbit", tabs: [
        .init(windowID: "window:w", label: "api", panes: [.init(blockID: "block:b", label: "shell", rect: [0, 0, 1, 1], preview: ["secret-looking text"])])
    ])])
    private func defaults() -> UserDefaults {
        let name = "volant.tests.rex-overview." + UUID().uuidString
        let suite = UserDefaults(suiteName: name)!
        suite.removePersistentDomain(forName: name)
        return suite
    }

    func testScreenTextNeedsBothPermissionAndPreviewMode() async throws {
        let model = RexOverviewModel(defaults: defaults())
        var asked: [Bool] = [], reply: Reply?
        model.reader = { _, preview, next in asked.append(preview); reply = next }
        model.connect()
        reply?(try JSONEncoder().encode(overview), 1, nil)
        await drain()
        XCTAssertNil(model.overview.sessions.first?.tabs.first?.panes.first?.preview, "status mode drops screen text even if the helper sent it")
        model.mode = .preview
        XCTAssertFalse(model.readsPreviews, "preview mode alone does not read screens")
        model.allowPreviews(true)
        reply?(try JSONEncoder().encode(overview), 2, nil)
        await drain()
        XCTAssertEqual(model.overview.sessions.first?.tabs.first?.panes.first?.preview, ["secret-looking text"])
        XCTAssertEqual(asked.last, true)
        model.mode = .status
        XCTAssertNil(model.overview.sessions.first?.tabs.first?.panes.first?.preview, "leaving preview mode drops screen text at once")
        XCTAssertEqual(asked.last, false)
        model.disconnect()
        XCTAssertTrue(model.overview.sessions.isEmpty, "closing forgets everything read")
    }

    func testPreviewChoiceIsRememberedPerMac() {
        let suite = defaults()
        RexOverviewModel(defaults: suite).allowPreviews(true)
        XCTAssertTrue(RexOverviewModel(defaults: suite).previewsAllowed)
        XCTAssertFalse(RexOverviewModel(defaults: defaults()).previewsAllowed, "off until turned on")
    }
}
