import XCTest
import VolantCore
@testable import Volant

final class AIConfigurationTests: XCTestCase {
    func testChatConnectsWithoutProjectAndPreservesActiveConversation() {
        let model = isolatedACPModel()
        var connects = 0
        XCTAssertFalse(model.openChat(configuration: nil) { connects += 1 })
        XCTAssertFalse(model.openChat(configuration: AIConfiguration()) { connects += 1 })
        var config = AIConfiguration(); config.provider = "claude"
        XCTAssertTrue(model.openChat(configuration: config) { connects += 1; model.state.phase = "ready" })
        XCTAssertEqual(connects, 1)
        XCTAssertEqual(model.project, "")
        model.draft = "Unfinished question"
        XCTAssertTrue(model.openChat(configuration: nil) { connects += 1 })
        XCTAssertEqual(connects, 1)
        XCTAssertEqual(model.draft, "Unfinished question")
        model.state.phase = "disconnected"
    }

    func testConfiguringACPDoesNotReplaceActiveConversation() {
        let model = isolatedACPModel()
        var config = AIConfiguration(); config.provider = "codex"; config.project = "/tmp/project"
        model.configure(config)
        XCTAssertEqual(model.provider, "codex")
        XCTAssertEqual(model.project, "/tmp/project")
        XCTAssertFalse(model.active)
        model.state.phase = "working"
        config.provider = "claude"; config.project = "/tmp/other"
        model.configure(config)
        XCTAssertEqual(model.provider, "codex")
        XCTAssertEqual(model.project, "/tmp/project")
        model.state.phase = "disconnected"
    }

    /// Lets main-queue replies scheduled so far run before the test continues.
    private func drain() async { await withCheckedContinuation { continuation in DispatchQueue.main.async { continuation.resume() } } }

    /// Agent detection in AI Settings, through an injected reader instead of the agent helper.
    @MainActor
    func testDetectionSortsReadyAgentsFirstAndReportsFailures() async throws {
        let detection = ACPAgentDetection()
        detection.reader = { reply in
            reply(try? JSONEncoder().encode([
                ACPAgentAvailability(provider: "gemini", state: .notInstalled, detail: "Gemini CLI was not found.", path: nil),
                ACPAgentAvailability(provider: "codex", state: .needsAdapter, detail: "Adapter missing.", path: nil),
                ACPAgentAvailability(provider: "qwen", state: .ready, detail: "Found at /opt/homebrew/bin/qwen", path: "/opt/homebrew/bin/qwen")
            ]), nil)
        }
        detection.detect(); await drain()
        XCTAssertEqual(detection.agents.map(\.provider), ["qwen", "codex", "gemini"])
        detection.reader = { $0(nil, "The agent helper is unavailable.") }
        detection.detect(); await drain()
        XCTAssertEqual(detection.message, "The agent helper is unavailable.")
    }
}
