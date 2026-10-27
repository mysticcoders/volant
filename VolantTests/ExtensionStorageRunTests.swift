import XCTest
import VolantCore
@testable import Volant

/// Saving and sending per-extension data, with a scripted module in place of the extension helper.
/// Every file is temporary and fictional; nothing touches the owner's Extensions or data folders.
@MainActor
final class ExtensionStorageRunTests: XCTestCase {
    private var root: URL!
    private var config: URL { root.appendingPathComponent("config.json") }
    private var folder: URL { root.appendingPathComponent("reader", isDirectory: true) }

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("storage-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try Data(#"{"extensions":{},"communityExtensionsAllowed":true}"#.utf8).write(to: config)
    }

    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: root) }

    /// An enabled list extension; `storage` decides whether it declares storage.
    private func manager(storage: Bool = true) throws -> (ExtensionManager, InstalledExtension) {
        let module = Data([0, 97, 115, 109, 1, 0, 0, 0, 5, 4, 1, 1, 1, 1])
        try module.write(to: folder.appendingPathComponent("reader.wasm"))
        let manifest = ExtensionManifest(id: "community.fictional.reader", name: "Fictional Reader", version: "1", module: "reader.wasm",
                                         capabilities: [], timeoutSeconds: 2, sha256: Integrity.sha256(module), output: "items",
                                         storage: storage ? true : nil)
        try JSONEncoder().encode(manifest).write(to: folder.appendingPathComponent("manifest.json"))
        let manager = ExtensionManager(configURL: config, roots: [folder], dataDirectory: root.appendingPathComponent("ExtensionData"))
        manager.reload()
        try manager.setEnabled(try XCTUnwrap(manager.extensions.first), true)
        return (manager, try XCTUnwrap(manager.extensions.first))
    }

    /// Replies with each string in turn and records the requests.
    private func script(_ manager: ExtensionManager, _ replies: [String]) -> () -> [String] {
        var queue = replies, requests: [String] = []
        manager.invokeOverride = { _, input, completion in
            requests.append(input)
            completion(.success(queue.isEmpty ? #"{"items":[]}"# : queue.removeFirst()))
        }
        return { requests }
    }

    private func items(_ manager: ExtensionManager, _ ext: InstalledExtension) -> Result<[ExtensionItem], Error> {
        var outcome: Result<[ExtensionItem], Error>?
        manager.runItems(ext, query: "", fetch: { _, _, _ in XCTFail("No hosts, no fetch") }) { outcome = $0 }
        return outcome!
    }

    private func json(_ text: String) throws -> JSONValue { try JSONDecoder().decode(JSONValue.self, from: Data(text.utf8)) }

    func testSavedDataIsSentWithTheNextRequest() throws {
        let (manager, ext) = try manager()
        let requests = script(manager, [#"{"items":[{"title":"One"}],"storage":{"pinned":["1"]}}"#, #"{"items":[]}"#])
        XCTAssertEqual(try items(manager, ext).get().map(\.title), ["One"])
        XCTAssertTrue(requests()[0].contains(#""storage":{}"#), "The first run gets an empty object")
        XCTAssertEqual(manager.storedData(ext), try json(#"{"pinned":["1"]}"#))
        _ = items(manager, ext)
        XCTAssertTrue(requests()[1].contains(#""storage":{"pinned":["1"]}"#))
    }

    func testExtensionsWithoutStorageNeitherReceiveNorSaveIt() throws {
        let (manager, ext) = try manager(storage: false)
        let requests = script(manager, [#"{"items":[],"storage":{"sneaky":true}}"#])
        _ = items(manager, ext)
        XCTAssertFalse(requests()[0].contains("storage"))
        XCTAssertFalse(manager.hasStoredData(ext))
    }

    func testOversizedOrMalformedStorageKeepsThePreviousData() throws {
        let (manager, ext) = try manager()
        _ = script(manager, [#"{"items":[],"storage":{"kept":1}}"#,
                             #"{"items":[],"storage":{"text":""# + String(repeating: "x", count: ExtensionStorage.maximumBytes) + #""}}"#,
                             #"{"items":[],"storage":["not","an","object"]}"#])
        _ = items(manager, ext)
        XCTAssertThrowsError(try items(manager, ext).get()) { XCTAssertFalse($0.localizedDescription.contains("xxxx")) }
        XCTAssertThrowsError(try items(manager, ext).get())
        XCTAssertEqual(manager.storedData(ext), try json(#"{"kept":1}"#))
    }

    func testRevokedOrCommunityOffRunsDiscardTheirStorage() throws {
        let (manager, ext) = try manager()
        manager.invokeOverride = { _, _, completion in
            try? manager.setEnabled(ext, false)
            completion(.success(#"{"items":[],"storage":{"late":true}}"#))
        }
        _ = items(manager, ext)
        XCTAssertFalse(manager.hasStoredData(ext), "A run disabled before its reply saves nothing")
        try manager.setEnabled(try XCTUnwrap(manager.extensions.first), true)
        let current = try XCTUnwrap(manager.extensions.first)
        manager.invokeOverride = { _, _, completion in
            try? manager.setCommunityAllowed(false, expected: true)
            completion(.success(#"{"items":[],"storage":{"late":true}}"#))
        }
        _ = items(manager, current)
        XCTAssertFalse(manager.hasStoredData(current), "Turning community extensions off discards the reply")
    }

    func testAnOlderRunCannotOverwriteANewerSave() throws {
        let (manager, ext) = try manager()
        var pending: [(Result<String, Error>) -> Void] = []
        manager.invokeOverride = { _, _, completion in pending.append(completion) }
        manager.runItems(ext, query: "") { _ in }
        manager.runItems(ext, query: "") { _ in }
        pending[1](.success(#"{"items":[],"storage":{"run":2}}"#))
        pending[0](.success(#"{"items":[],"storage":{"run":1}}"#))
        XCTAssertEqual(manager.storedData(ext), try json(#"{"run":2}"#))
    }

    func testActionsAndOpenedRowsSendTheRowAndSaveTheReply() throws {
        let (manager, ext) = try manager()
        let requests = script(manager, [#"{"items":[{"title":"Pinned"}],"storage":{"pinned":["s1"]}}"#, #"{"storage":{"pinned":["s1"],"read":["s1"]}}"#])
        let item = ExtensionItem(title: "Story", url: "https://news.example.com/s1", actions: [.init(id: "pin", title: "Pin Story")])
        var redraw: [ExtensionItem]?
        manager.runAction(ext, item: item, action: "pin", query: "new") { redraw = try? $0.get().items }
        XCTAssertEqual(redraw?.map(\.title), ["Pinned"])
        XCTAssertTrue(requests()[0].contains(#""action":"pin""#) && requests()[0].contains(#""phase":"action""#) && requests()[0].contains(#""query":"new""#))
        XCTAssertTrue(requests()[0].contains(#""url":"https:\/\/news.example.com\/s1""#))
        var opened: [ExtensionItem]? = [ExtensionItem(title: "placeholder")]
        manager.runAction(ext, item: item, action: nil, query: "new") { opened = try? $0.get().items }
        XCTAssertNil(opened, "A storage-only reply leaves the rows alone")
        XCTAssertTrue(requests()[1].contains(#""phase":"opened""#) && !requests()[1].contains(#""action""#))
        XCTAssertEqual(manager.storedData(ext), try json(#"{"pinned":["s1"],"read":["s1"]}"#))
    }

    func testClearDataAndUninstallRemoveSavedDataButDisablingKeepsIt() throws {
        let (manager, ext) = try manager()
        _ = script(manager, [#"{"items":[],"storage":{"a":1}}"#, #"{"items":[],"storage":{"b":2}}"#])
        _ = items(manager, ext)
        try manager.setEnabled(ext, false)
        XCTAssertTrue(manager.hasStoredData(ext), "Turning an extension off keeps its data")
        try manager.clearStoredData(ext)
        XCTAssertFalse(manager.hasStoredData(ext))
        try manager.setEnabled(try XCTUnwrap(manager.extensions.first), true)
        _ = items(manager, try XCTUnwrap(manager.extensions.first))
        XCTAssertTrue(manager.hasStoredData(ext))
        try manager.uninstall(try XCTUnwrap(manager.extensions.first)) { try FileManager.default.removeItem(at: $0) }
        XCTAssertFalse(manager.hasStoredData(ext))
    }

    func testDataFilesAreNamedByHashNotByID() throws {
        let store = ExtensionDataStore(directory: root.appendingPathComponent("ExtensionData"))
        try store.save(.object(["a": .number(1)]), for: "../../escape")
        let names = try FileManager.default.contentsOfDirectory(atPath: store.directory.path)
        XCTAssertEqual(names.count, 1)
        XCTAssertFalse(names[0].contains(".."))
        XCTAssertEqual(store.load("../../escape"), .object(["a": .number(1)]))
    }

    func testACancelledRunDropsTheReplyAndItsStorage() throws {
        let (manager, ext) = try manager()
        var pending: ((Result<String, Error>) -> Void)?
        manager.invokeOverride = { _, _, completion in pending = completion }
        var outcome: Result<[ExtensionItem], Error>?
        manager.runItems(ext, query: "new", fetch: { _, _, _ in XCTFail("No hosts, no fetch") }) { outcome = $0 }
        manager.cancelItemsRun()
        XCTAssertNil(outcome, "A module already running finishes before the run completes")
        try XCTUnwrap(pending)(.success(#"{"items":[{"title":"Stale"}],"storage":{"pinned":["stale"]}}"#))
        guard case .failure(let error) = try XCTUnwrap(outcome) else { return XCTFail("A cancelled run must not show its rows") }
        XCTAssertTrue(ExtensionManager.ExtensionError.isCancellation(error))
        XCTAssertFalse(manager.hasStoredData(ext), "A cancelled run must not save its storage")
    }
}
