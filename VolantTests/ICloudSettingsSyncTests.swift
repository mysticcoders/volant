import XCTest
import VolantCore
@testable import Volant

private final class MemoryStore: SettingsKeyValueStore {
    var values: [String: Any] = [:]
    var available = true
    func object(forKey key: String) -> Any? { values[key] }
    func set(_ value: Any?, forKey key: String) { values[key] = value }
    func synchronize() -> Bool { available }
}

final class ICloudSettingsSyncTests: XCTestCase {
    private var root: URL!
    private var configURL: URL!
    private var stateURL: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("volant-icloud-" + UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        configURL = root.appendingPathComponent("config.json")
        stateURL = root.appendingPathComponent("icloud-sync.json")
    }

    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: root) }

    private func copies() throws -> [String] {
        try FileManager.default.contentsOfDirectory(atPath: root.path).filter { $0.hasPrefix("config.before-icloud-") }
    }

    func testFirstEnableKeepsACopyAdoptsCloudValuesAndSendsTheRest() throws {
        try Data(#"{"summonHotKey":"cmd+space","notesHotKey":"option+n","showInDock":false}"#.utf8).write(to: configURL)
        let store = MemoryStore()
        store.values["settings.summonHotKey"] = SettingsSync.Entry(value: try SettingsSync.canonical("ctrl+space"), modified: Date()).propertyList
        var reloads = 0
        let sync = ICloudSettingsSync(store: { store }, configURL: configURL, stateURL: stateURL, onApplied: { reloads += 1 })
        sync.update(enabled: true)
        let config = try JSONDecoder().decode(Preferences.self, from: Data(contentsOf: configURL))
        XCTAssertEqual(config.summonHotKey, "ctrl+space")
        XCTAssertFalse(config.showInDock)
        XCTAssertEqual(reloads, 1)
        XCTAssertEqual(try copies().count, 1)
        XCTAssertNotNil(SettingsSync.Entry(propertyList: store.values["settings.notesHotKey"]))
        XCTAssertNil(store.values["settings.showInDock"])
        guard case .synced = sync.status else { return XCTFail("\(sync.status)") }
    }

    func testLocalEditIsSentOnNextPassWithoutAnotherCopy() throws {
        try Data(#"{"aliases":{}}"#.utf8).write(to: configURL)
        let store = MemoryStore()
        let sync = ICloudSettingsSync(store: { store }, configURL: configURL, stateURL: stateURL, onApplied: {})
        sync.update(enabled: true)
        try Preferences.updateBoolean("showInDock", value: false, at: configURL)
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: configURL)) as? [String: Any])
        object["aliases"] = ["s": "Safari"]
        try JSONSerialization.data(withJSONObject: object).write(to: configURL)
        sync.sync()
        let sent = try XCTUnwrap(SettingsSync.Entry(propertyList: store.values["settings.aliases"]))
        XCTAssertEqual(sent.value, try SettingsSync.canonical(["s": "Safari"]))
        XCTAssertEqual(try copies().count, 1)
    }

    func testUnavailableICloudChangesNothing() throws {
        let original = Data(#"{"summonHotKey":"cmd+space"}"#.utf8)
        try original.write(to: configURL)
        let store = MemoryStore()
        store.available = false
        let sync = ICloudSettingsSync(store: { store }, configURL: configURL, stateURL: stateURL, onApplied: { XCTFail("reloaded") })
        sync.update(enabled: true)
        XCTAssertEqual(sync.status, .unavailable)
        XCTAssertEqual(try Data(contentsOf: configURL), original)
        XCTAssertTrue(store.values.isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: stateURL.path))
    }

    func testMalformedConfigIsLeftInPlaceAndReported() throws {
        let original = Data("{ not json".utf8)
        try original.write(to: configURL)
        let store = MemoryStore()
        let sync = ICloudSettingsSync(store: { store }, configURL: configURL, stateURL: stateURL, onApplied: { XCTFail("reloaded") })
        sync.update(enabled: true)
        XCTAssertEqual(try Data(contentsOf: configURL), original)
        XCTAssertTrue(store.values.isEmpty)
        guard case .attention = sync.status else { return XCTFail("\(sync.status)") }
    }

    func testTurningOffForgetsBaselineAndAccountChangeStartsOver() throws {
        try Data(#"{"summonHotKey":"cmd+space"}"#.utf8).write(to: configURL)
        let store = MemoryStore()
        let sync = ICloudSettingsSync(store: { store }, configURL: configURL, stateURL: stateURL, onApplied: {})
        sync.update(enabled: true)
        XCTAssertTrue(FileManager.default.fileExists(atPath: stateURL.path))
        store.values["settings.summonHotKey"] = SettingsSync.Entry(value: try SettingsSync.canonical("ctrl+space"), modified: .distantPast).propertyList
        sync.cloudChanged(reason: NSUbiquitousKeyValueStoreAccountChange)
        XCTAssertEqual(try JSONDecoder().decode(Preferences.self, from: Data(contentsOf: configURL)).summonHotKey, "ctrl+space")
        sync.update(enabled: false)
        XCTAssertFalse(FileManager.default.fileExists(atPath: stateURL.path))
        XCTAssertEqual(sync.status, .off)
    }
}
