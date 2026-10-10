import Foundation
import XCTest

@testable import VolantCore

/// Send to Several's plan: one target per chosen conversation, a capped total, and a workspace for
/// every target once a folder is set.
final class ACPFanOutTests: XCTestCase {
    private func settings(project: String = "", isolate: Bool = false, fanOut: Int = ACPFanOut.defaultLimit) -> AIConfiguration {
        var config = AIConfiguration()
        config.provider = "claude"; config.project = project; config.isolate = isolate; config.fanOut = fanOut
        return config
    }

    private func refusal(_ body: () throws -> [AIConfiguration]) -> String? {
        do { _ = try body(); return nil } catch { return (error as? ACPFanOut.Refusal)?.message ?? "\(error)" }
    }

    func testTargetsFollowTheProviderOrderAndKeepTheSettings() throws {
        let targets = try ACPFanOut.targets(prompt: "Fix the fictional build", counts: [.codex: 1, .claude: 2, .gemini: 0], configuration: settings())
        XCTAssertEqual(targets.map(\.provider), ["claude", "claude", "codex"])
        XCTAssertTrue(targets.allSatisfy { $0.connection == .acp && $0.project.isEmpty && !$0.isolate && $0.isConfigured })
    }

    func testAFolderGivesEveryTargetItsOwnWorkspace() throws {
        let off = try ACPFanOut.targets(prompt: "Fictional task", counts: [.claude: 1, .qwen: 1], configuration: settings(project: "/tmp/fictional-project"))
        XCTAssertEqual(off.map(\.project), ["/tmp/fictional-project", "/tmp/fictional-project"])
        XCTAssertTrue(off.allSatisfy(\.isolate), "isolated even with the setting off")
        let general = try ACPFanOut.targets(prompt: "Fictional task", counts: [.claude: 2], configuration: settings(isolate: true))
        XCTAssertFalse(general.contains(where: \.isolate), "general chat needs no workspace")
    }

    func testTheTotalIsCappedByTheSetting() throws {
        XCTAssertEqual(try ACPFanOut.targets(prompt: "Fictional task", counts: [.claude: 2, .codex: 2], configuration: settings()).count, 4)
        XCTAssertEqual(refusal { try ACPFanOut.targets(prompt: "Fictional task", counts: [.claude: 3, .codex: 2], configuration: self.settings()) },
                       "Choose at most 4 agents.")
        XCTAssertEqual(try ACPFanOut.targets(prompt: "Fictional task", counts: [.claude: 6], configuration: settings(fanOut: 6)).count, 6)
        XCTAssertEqual(refusal { try ACPFanOut.targets(prompt: "Fictional task", counts: [.claude: Int.max, .codex: 1], configuration: self.settings()) },
                       "Choose at most 4 agents.", "a huge count is refused before it is summed")
    }

    func testRefusalsStartNothing() {
        var api = settings(); api.connection = .byok
        XCTAssertEqual(refusal { try ACPFanOut.targets(prompt: "Fictional task", counts: [.claude: 2], configuration: api) },
                       "Send to Several starts ACP agents. Choose ACP in AI Settings.")
        XCTAssertEqual(refusal { try ACPFanOut.targets(prompt: " \n ", counts: [.claude: 2], configuration: self.settings()) }, "Write a prompt first.")
        XCTAssertEqual(refusal { try ACPFanOut.targets(prompt: String(repeating: "a", count: ACPFanOut.promptLimit + 1), counts: [.claude: 2], configuration: self.settings()) },
                       "Enter a prompt of at most 64 KB.")
        XCTAssertNil(refusal { try ACPFanOut.targets(prompt: String(repeating: "a", count: ACPFanOut.promptLimit), counts: [.claude: 2], configuration: self.settings()) })
        XCTAssertEqual(refusal { try ACPFanOut.targets(prompt: "Fictional task", counts: [:], configuration: self.settings()) }, "Choose at least one agent.")
        XCTAssertEqual(refusal { try ACPFanOut.targets(prompt: "Fictional task", counts: [.claude: 0], configuration: self.settings()) }, "Choose at least one agent.")
        XCTAssertEqual(refusal { try ACPFanOut.targets(prompt: "Fictional task", counts: [.claude: -1, .codex: 2], configuration: self.settings()) },
                       "Choose how many of each agent to start.")
    }

    func testTheSettingIsClampedToTwoThroughTheLiveLimit() {
        XCTAssertEqual(ACPFanOut.limits, 2...ACPConversationLimit.live)
        XCTAssertEqual(ACPFanOut.clamp(0), 2)
        XCTAssertEqual(ACPFanOut.clamp(-5), 2)
        XCTAssertEqual(ACPFanOut.clamp(5), 5)
        XCTAssertEqual(ACPFanOut.clamp(99), ACPConversationLimit.live)
        XCTAssertEqual(refusal { try ACPFanOut.targets(prompt: "Fictional task", counts: [.claude: 7], configuration: self.settings(fanOut: 40)) },
                       "Choose at most 6 agents.", "a stored value past the limit plans no more than the limit")
    }

    func testTheSettingDecodesWithADefaultAndClamps() throws {
        func decoded(_ json: String) throws -> AIConfiguration { try JSONDecoder().decode(AIConfiguration.self, from: Data(json.utf8)) }
        XCTAssertEqual(AIConfiguration().fanOut, 4)
        XCTAssertEqual(try decoded(#"{"provider":"claude"}"#).fanOut, 4, "an older file reads as the default")
        XCTAssertEqual(try decoded(#"{"fanOut":3}"#).fanOut, 3)
        XCTAssertEqual(try decoded(#"{"fanOut":1}"#).fanOut, 2)
        XCTAssertEqual(try decoded(#"{"fanOut":12}"#).fanOut, ACPConversationLimit.live)
    }

    func testTheSettingIsSavedBesideUnknownFields() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("volant-fan-out-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: url) }
        try Data(#"{"ai":{"provider":"claude","future":42}}"#.utf8).write(to: url)
        let original = try AIConfiguration.load(at: url)
        var changed = original; changed.fanOut = 5
        try changed.save(at: url, expected: original)
        XCTAssertEqual(try AIConfiguration.load(at: url).fanOut, 5)
        let ai = try XCTUnwrap((JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])?["ai"] as? [String: Any])
        XCTAssertEqual(ai["fanOut"] as? Int, 5)
        XCTAssertEqual(ai["future"] as? Int, 42)
    }
}
