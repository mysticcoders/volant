import Foundation
import XCTest

@testable import VolantCore

/// The storage boundary: what an extension may save, how it travels in requests and replies, and how
/// row actions are trimmed before the launcher shows them.
final class ExtensionStorageTests: XCTestCase {
    private func value(_ json: String) throws -> JSONValue { try JSONDecoder().decode(JSONValue.self, from: Data(json.utf8)) }

    func testOnlyBoundedObjectsCanBeSavedAndEncodingIsCanonical() throws {
        let saved = try ExtensionStorage.encode(try value(#"{"pinned":["b","a"],"hidden":{"x":true},"count":3}"#))
        XCTAssertEqual(String(decoding: saved, as: UTF8.self), #"{"count":3,"hidden":{"x":true},"pinned":["b","a"]}"#)
        XCTAssertEqual(ExtensionStorage.decode(saved), try value(#"{"pinned":["b","a"],"hidden":{"x":true},"count":3}"#))
        XCTAssertThrowsError(try ExtensionStorage.encode(try value(#"["a"]"#))) { XCTAssertEqual($0 as? ExtensionStorageError, .notObject) }
        XCTAssertThrowsError(try ExtensionStorage.encode(.string("a"))) { XCTAssertEqual($0 as? ExtensionStorageError, .notObject) }
        var deep = JSONValue.string("leaf")
        for _ in 0..<ExtensionStorage.maximumDepth { deep = .object(["n": deep]) }
        XCTAssertNoThrow(try ExtensionStorage.encode(deep))
        XCTAssertThrowsError(try ExtensionStorage.encode(.object(["n": deep]))) { XCTAssertEqual($0 as? ExtensionStorageError, .tooDeep) }
        let large = JSONValue.object(["text": .string(String(repeating: "x", count: ExtensionStorage.maximumBytes))])
        XCTAssertThrowsError(try ExtensionStorage.encode(large)) {
            guard case .tooLarge = $0 as? ExtensionStorageError else { return XCTFail("Expected tooLarge, got \($0)") }
            XCTAssertFalse($0.localizedDescription.contains("xxxx"), "Errors never repeat stored values")
        }
    }

    func testUnreadableSavedDataReadsAsEmpty() {
        XCTAssertEqual(ExtensionStorage.decode(nil), ExtensionStorage.empty)
        XCTAssertEqual(ExtensionStorage.decode(Data("not json".utf8)), ExtensionStorage.empty)
        XCTAssertEqual(ExtensionStorage.decode(Data("[1,2]".utf8)), ExtensionStorage.empty)
        XCTAssertEqual(ExtensionStorage.decode(Data(count: ExtensionStorage.maximumBytes + 1)), ExtensionStorage.empty)
    }

    func testStorageNeedsAListExtensionAndLeavesOtherFingerprintsAlone() throws {
        var manifest = ExtensionManifest(id: "community.fictional.reader", name: "Reader", version: "1", module: "reader.wasm",
                                         capabilities: [], sha256: String(repeating: "a", count: 64), output: "items")
        let encoder = JSONEncoder(); encoder.outputFormatting = .sortedKeys
        XCTAssertFalse(String(decoding: try encoder.encode(manifest), as: UTF8.self).contains("storage"))
        manifest.storage = true
        XCTAssertNoThrow(try manifest.validate())
        XCTAssertTrue(manifest.usesStorage)
        manifest.output = nil
        XCTAssertThrowsError(try manifest.validate(), "Text extensions cannot declare storage yet")
    }

    func testRequestsCarryStorageActionAndItemOnlyWhenGiven() throws {
        let now = Date(timeIntervalSince1970: 1_791_000_000)
        let item = ExtensionItem(title: "Story", url: "https://news.example.com/1")
        let text = try ExtensionNetwork.request(phase: "action", query: "", now: now, storage: try value(#"{"pinned":[]}"#), action: "pin", item: item, units: "metric")
        XCTAssertEqual(text, #"{"action":"pin","item":{"title":"Story","url":"https:\/\/news.example.com\/1"},"now":1791000000,"phase":"action","query":"","storage":{"pinned":[]},"units":"metric"}"#)
    }

    func testRepliesMayCarryItemsStorageOrBoth() throws {
        XCTAssertEqual(try ExtensionNetwork.reply(from: #"{"storage":{"a":1}}"#), .init(items: nil, storage: try value(#"{"a":1}"#)))
        XCTAssertEqual(try ExtensionNetwork.reply(from: #"{"items":[{"title":"One"}]}"#).items?.map(\.title), ["One"])
        let both = try ExtensionNetwork.reply(from: #"{"items":[],"storage":{}}"#)
        XCTAssertEqual(both.items, [])
        XCTAssertEqual(both.storage, ExtensionStorage.empty)
        XCTAssertThrowsError(try ExtensionNetwork.reply(from: #"{"fetch":[]}"#))
        XCTAssertThrowsError(try ExtensionNetwork.reply(from: "nope"))
    }

    func testRowActionsAreTrimmedDedupedAndBounded() throws {
        let json = #"{"items":[{"title":"Story","onOpen":false,"actions":["#
            + #"{"id":"pin","title":"Pin Story"},{"id":"pin","title":"Duplicate"},{"id":"Bad ID","title":"No"},{"id":"x","title":""},"#
            + #"{"id":"a","title":"A"},{"id":"b","title":"B"},{"id":"c","title":"C"},{"id":"d","title":"D"},{"id":"e","title":"E"},{"id":"f","title":"F"}]},"#
            + #"{"title":"Read","onOpen":true}]}"#
        let items = try XCTUnwrap(try ExtensionNetwork.reply(from: json).items)
        XCTAssertEqual(items[0].actions?.map(\.id), ["pin", "a", "b", "c", "d", "e"])
        XCTAssertNil(items[0].onOpen)
        XCTAssertNil(items[1].actions)
        XCTAssertEqual(items[1].onOpen, true)
    }
}
