import XCTest

@testable import VolantCore

final class ExtensionPreferenceTests: XCTestCase {
    private let hide = ExtensionPreference(id: "hideDomains", type: .text, title: "Hidden domains", defaultValue: .string(""), maxLength: 100)
    private let sort = ExtensionPreference(id: "sort", type: .dropdown, title: "Sort",
                                           choices: [ExtensionFilter(id: "top", title: "Top"), ExtensionFilter(id: "new", title: "New")])
    private let scores = ExtensionPreference(id: "showScores", type: .toggle, title: "Show scores", defaultValue: .bool(true))
    private let limit = ExtensionPreference(id: "limit", type: .number, title: "Rows", defaultValue: .number(30), min: 5, max: 50)

    private func manifest(_ preferences: [ExtensionPreference]?, output: String? = "items") -> ExtensionManifest {
        ExtensionManifest(id: "community.fictional.reader", name: "Fictional Reader", version: "1", module: "reader.wasm",
                          capabilities: [], timeoutSeconds: 2, sha256: String(repeating: "a", count: 64), output: output, preferences: preferences)
    }

    func testEachTypeValidatesItsOwnFields() {
        for preference in [hide, sort, scores, limit] { XCTAssertTrue(preference.isValid, preference.id) }
        XCTAssertFalse(ExtensionPreference(id: "bad id", type: .toggle, title: "x").isValid, "Ids are letters, digits, - and _")
        XCTAssertFalse(ExtensionPreference(id: "a", type: .toggle, title: "Two\nlines").isValid)
        XCTAssertFalse(ExtensionPreference(id: "a", type: .dropdown, title: "One choice", choices: [ExtensionFilter(id: "x", title: "X")]).isValid)
        XCTAssertFalse(ExtensionPreference(id: "a", type: .number, title: "No range").isValid)
        XCTAssertFalse(ExtensionPreference(id: "a", type: .number, title: "Backwards", min: 10, max: 1).isValid)
        XCTAssertFalse(ExtensionPreference(id: "a", type: .text, title: "Huge", maxLength: 5000).isValid)
        XCTAssertFalse(ExtensionPreference(id: "a", type: .toggle, title: "Wrong default", defaultValue: .string("yes")).isValid)
        XCTAssertFalse(ExtensionPreference(id: "a", type: .number, title: "Out of range", defaultValue: .number(99), min: 1, max: 10).isValid)
        XCTAssertFalse(ExtensionPreference(id: "a", type: .toggle, title: "Stray range", min: 1, max: 2).isValid)
    }

    func testManifestAcceptsPreferencesOnlyOnExtensionsThatReceiveRequests() throws {
        XCTAssertNoThrow(try manifest([hide, sort, scores, limit]).validate())
        XCTAssertThrowsError(try manifest([hide], output: nil).validate(), "Plain text extensions have no request to carry them")
        var json = manifest([hide], output: nil); json.input = "json"
        XCTAssertNoThrow(try json.validate(), "A text extension that takes JSON requests can have preferences")
        XCTAssertThrowsError(try manifest([hide, hide]).validate(), "Duplicate ids")
        let thirteen = (1...13).map { ExtensionPreference(id: "p\($0)", type: .toggle, title: "P\($0)") }
        XCTAssertThrowsError(try manifest(thirteen).validate())
        let decoded = try JSONDecoder().decode(ExtensionManifest.self, from: Data(#"""
        {"abiVersion":1,"id":"community.fictional.reader","name":"Fictional Reader","version":"1","module":"reader.wasm","capabilities":[],
         "sha256":"\#(String(repeating: "a", count: 64))","output":"items",
         "preferences":[{"id":"limit","type":"number","title":"Rows","default":30,"min":5,"max":50}]}
        """#.utf8))
        XCTAssertEqual(decoded.declaredPreferences, [limit])
        XCTAssertNoThrow(try decoded.validate())
    }

    func testResolveUsesStoredValuesThatStillFitAndFallsBackOtherwise() {
        let declared = [hide, sort, scores, limit]
        XCTAssertEqual(ExtensionPreferences.resolve(declared, stored: [:]),
                       ["hideDomains": .string(""), "sort": .string("top"), "showScores": .bool(true), "limit": .number(30)])
        let stored: [String: JSONValue] = ["hideDomains": .string("fictional.example"), "sort": .string("new"),
                                           "showScores": .bool(false), "limit": .number(12), "removed": .string("old")]
        XCTAssertEqual(ExtensionPreferences.resolve(declared, stored: stored),
                       ["hideDomains": .string("fictional.example"), "sort": .string("new"), "showScores": .bool(false), "limit": .number(12)],
                       "Undeclared keys are dropped")
        let stale: [String: JSONValue] = ["hideDomains": .string(String(repeating: "x", count: 101)), "sort": .string("ask"),
                                          "showScores": .string("true"), "limit": .number(500)]
        XCTAssertEqual(ExtensionPreferences.resolve(declared, stored: stale), ExtensionPreferences.resolve(declared, stored: [:]),
                       "Values that no longer fit the declaration fall back")
        XCTAssertNil(hide.accepted(.string("two\nlines")))
    }

    func testRequestCarriesPreferencesOnlyWhenThereAreAny() throws {
        let now = Date(timeIntervalSince1970: 1_000)
        let with = try ExtensionNetwork.request(phase: "plan", query: "", now: now, units: "metric", preferences: ["limit": .number(12)])
        XCTAssertTrue(with.contains(#""preferences":{"limit":12}"#), with)
        XCTAssertFalse(try ExtensionNetwork.request(phase: "plan", query: "", now: now, units: "metric", preferences: [:]).contains("preferences"))
        XCTAssertFalse(try ExtensionNetwork.request(phase: "plan", query: "", now: now, units: "metric").contains("preferences"))
    }
}
