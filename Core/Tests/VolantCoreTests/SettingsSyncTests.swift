import XCTest

@testable import VolantCore

final class SettingsSyncTests: XCTestCase {
    private let earlier = Date(timeIntervalSince1970: 1_000)
    private let later = Date(timeIntervalSince1970: 2_000)

    private func config(_ object: [String: Any]) throws -> Data {
        try JSONSerialization.data(withJSONObject: object)
    }

    private func entry(_ value: Any, at date: Date) throws -> SettingsSync.Entry {
        SettingsSync.Entry(value: try SettingsSync.canonical(value), modified: date)
    }

    private func object(_ data: Data?) throws -> [String: Any] {
        try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(data)) as? [String: Any])
    }

    func testFirstRunOnEmptyCloudSendsEverySyncedKeyAndNothingElse() throws {
        let local = try config(["summonHotKey": "cmd+space", "showInDock": false, "favoriteApps": ["com.apple.Safari"]])
        let outcome = try SettingsSync.reconcile(config: local, modified: earlier, remote: [:], state: .init(), now: later)
        XCTAssertNil(outcome.config)
        XCTAssertEqual(Set(outcome.uploads.keys), Set(SettingsSync.keys))
        XCTAssertEqual(outcome.uploads["summonHotKey"], try entry("cmd+space", at: later))
        XCTAssertEqual(outcome.uploads["notesHotKey"]?.value, try SettingsSync.canonical("option+n"))
        XCTAssertEqual(outcome.state.baseline.count, SettingsSync.keys.count)
    }

    func testFirstRunAdoptsCloudValuesAndPreservesLocalOnlyAndUnknownFields() throws {
        let local = try config(["snippets": [], "showInDock": false, "future": ["keep": 1], "appearance": ["theme": "light"]])
        let remote = ["snippets": try entry([["name": "Signature", "keyword": "sig", "body": "Thanks"]], at: earlier),
                      "appearance": try entry(["theme": "dark", "scale": 1.2, "opacity": 1, "newField": "kept"], at: earlier)]
        let outcome = try SettingsSync.reconcile(config: local, modified: later, remote: remote, state: .init())
        let result = try object(outcome.config)
        XCTAssertEqual(Set(outcome.received), ["snippets", "appearance"])
        XCTAssertEqual(result["showInDock"] as? Bool, false)
        XCTAssertNotNil(result["future"])
        XCTAssertEqual((result["appearance"] as? [String: Any])?["newField"] as? String, "kept")
        let decoded = try JSONDecoder().decode(Preferences.self, from: XCTUnwrap(outcome.config))
        XCTAssertEqual(decoded.appearance.theme, .dark)
        XCTAssertEqual(decoded.snippets.count, 1)
    }

    func testOnlyTheSideThatChangedSinceBaselineWins() throws {
        let base = SettingsSync.State(baseline: ["summonHotKey": try SettingsSync.canonical("option+space"),
                                                 "notesHotKey": try SettingsSync.canonical("option+n")])
        let local = try config(["summonHotKey": "cmd+space", "notesHotKey": "option+n"])
        let remote = ["summonHotKey": try entry("option+space", at: later), "notesHotKey": try entry("ctrl+n", at: earlier)]
        let outcome = try SettingsSync.reconcile(config: local, modified: earlier, remote: remote, state: base, now: later)
        let result = try object(outcome.config)
        XCTAssertEqual(result["summonHotKey"] as? String, "cmd+space")
        XCTAssertEqual(result["notesHotKey"] as? String, "ctrl+n")
        XCTAssertEqual(outcome.received, ["notesHotKey"])
        XCTAssertTrue(outcome.sent.contains("summonHotKey"))
        XCTAssertEqual(outcome.state.baseline["notesHotKey"], try SettingsSync.canonical("ctrl+n"))
        XCTAssertEqual(outcome.state.baseline["summonHotKey"], try SettingsSync.canonical("cmd+space"))
    }

    func testConcurrentEditsResolveToTheLaterChange() throws {
        let base = SettingsSync.State(baseline: ["aliases": try SettingsSync.canonical([String: String]())])
        let local = try config(["aliases": ["s": "Safari"]])
        let remote = ["aliases": try entry(["m": "Mail"], at: earlier)]
        let localWins = try SettingsSync.reconcile(config: local, modified: later, remote: remote, state: base, now: later)
        XCTAssertNil(localWins.config)
        XCTAssertTrue(localWins.sent.contains("aliases"))
        let cloudWins = try SettingsSync.reconcile(config: local, modified: earlier, remote: ["aliases": try entry(["m": "Mail"], at: later)], state: base)
        XCTAssertEqual((try object(cloudWins.config)["aliases"] as? [String: String]), ["m": "Mail"])
    }

    func testInvalidCloudValueIsNotAppliedOrRecorded() throws {
        let local = try config(["clipboardRetention": 500])
        let outcome = try SettingsSync.reconcile(config: local, modified: earlier, remote: ["clipboardRetention": try entry("many", at: later)], state: .init())
        XCTAssertNil(outcome.config)
        XCTAssertEqual(outcome.rejected, ["clipboardRetention"])
        XCTAssertNil(outcome.state.baseline["clipboardRetention"])
        XCTAssertNil(outcome.uploads["clipboardRetention"])
    }

    func testMalformedConfigExchangesNothing() {
        XCTAssertThrowsError(try SettingsSync.reconcile(config: Data("not json".utf8), modified: earlier, remote: [:], state: .init())) { error in
            XCTAssertEqual(error as? SettingsSync.Failure, .unreadableConfig)
        }
    }

    func testOversizedSettingsAreHeldBackWithoutAdvancingBaseline() throws {
        let text = String(repeating: "x", count: SettingsSync.byteBudget)
        let local = try config(["snippets": [["name": "Big", "keyword": "big", "body": text]]])
        let outcome = try SettingsSync.reconcile(config: local, modified: earlier, remote: [:], state: .init())
        XCTAssertTrue(outcome.overBudget)
        XCTAssertTrue(outcome.uploads.isEmpty)
        XCTAssertTrue(outcome.state.baseline.isEmpty)
    }

    func testEntryRoundTripsThroughPropertyListAndRejectsMalformedEnvelopes() throws {
        let original = try entry(["theme": "dark"], at: later)
        XCTAssertEqual(SettingsSync.Entry(propertyList: original.propertyList), original)
        XCTAssertNil(SettingsSync.Entry(propertyList: ["value": Data("{".utf8), "modified": 1.0]))
        XCTAssertNil(SettingsSync.Entry(propertyList: "text"))
        let pretty = ["value": Data("{ \"theme\" : \"dark\" }".utf8), "modified": later.timeIntervalSince1970] as [String: Any]
        XCTAssertEqual(SettingsSync.Entry(propertyList: pretty), original)
    }

    func testPreserveKeepsACopyAndNeverOverwritesAnEarlierOne() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("config.json")
        try Data(#"{"summonHotKey":"cmd+space"}"#.utf8).write(to: url)
        let copy = try SettingsSync.preserve(configAt: url, on: later)
        XCTAssertEqual(try Data(contentsOf: copy), try Data(contentsOf: url))
        let second = try SettingsSync.preserve(configAt: url, on: later)
        XCTAssertNotEqual(second, copy)
        XCTAssertEqual(try Data(contentsOf: second), try Data(contentsOf: url))
    }

    func testSyncSwitchIsAPatchableLocalSetting() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: url) }
        try Data(#"{"future":1}"#.utf8).write(to: url)
        XCTAssertFalse(try JSONDecoder().decode(Preferences.self, from: Data(contentsOf: url)).syncSettingsWithICloud)
        try Preferences.updateBoolean("syncSettingsWithICloud", value: true, at: url)
        XCTAssertTrue(try JSONDecoder().decode(Preferences.self, from: Data(contentsOf: url)).syncSettingsWithICloud)
        XCTAssertFalse(SettingsSync.keys.contains("syncSettingsWithICloud"))
    }
}
