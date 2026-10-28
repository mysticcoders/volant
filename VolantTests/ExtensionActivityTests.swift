import XCTest
import VolantCore
@testable import Volant

/// Host-observed extension activity: what Volant records at each boundary, in order and per run, and
/// that it never records the query, clipboard text, URL paths or rows. A scripted module stands in for
/// the extension helper; every file is temporary and fictional.
@MainActor
final class ExtensionActivityTests: XCTestCase {
    private var root: URL!
    private var config: URL { root.appendingPathComponent("config.json") }
    private var folder: URL { root.appendingPathComponent("reader", isDirectory: true) }
    private let recorder = ExtensionActivityRecorder()

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("activity-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try Data(#"{"extensions":{},"communityExtensionsAllowed":true}"#.utf8).write(to: config)
    }

    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: root) }

    /// An enabled list extension reading news.example.com, with storage and the clipboard permission.
    private func manager(enabled: Bool = true) throws -> (ExtensionManager, InstalledExtension) {
        let module = Data([0, 97, 115, 109, 1, 0, 0, 0, 5, 4, 1, 1, 1, 1])
        try module.write(to: folder.appendingPathComponent("reader.wasm"))
        let manifest = ExtensionManifest(id: "community.fictional.reader", name: "Fictional Reader", version: "2", module: "reader.wasm",
                                         capabilities: [], timeoutSeconds: 2, sha256: Integrity.sha256(module), hosts: ["news.example.com"],
                                         output: "items", storage: true, permissions: ["clipboard"])
        try JSONEncoder().encode(manifest).write(to: folder.appendingPathComponent("manifest.json"))
        let manager = ExtensionManager(configURL: config, roots: [folder], dataDirectory: root.appendingPathComponent("ExtensionData"))
        manager.activity = recorder
        manager.readClipboard = { "fictional clipboard secret" }
        manager.reload()
        if enabled { try manager.setEnabled(try XCTUnwrap(manager.extensions.first), true) }
        return (manager, try XCTUnwrap(manager.extensions.first))
    }

    private func script(_ manager: ExtensionManager, _ replies: [String]) {
        var queue = replies
        manager.invokeOverride = { _, _, completion in completion(.success(queue.isEmpty ? #"{"items":[]}"# : queue.removeFirst())) }
    }

    private func summary(_ events: [ExtensionActivity]) -> [String] {
        events.map { [$0.operation.rawValue, $0.outcome.rawValue, $0.detail].compactMap { $0 }.joined(separator: " ") }
    }

    func testAListRunIsRecordedInOrderUnderOneInvocationWithoutOwnerText() throws {
        let (manager, ext) = try manager()
        script(manager, [#"{"fetch":["https://news.example.com/search?q=fictional-secret-query"]}"#,
                         #"{"items":[{"title":"Private row title"}],"storage":{"seen":1}}"#])
        var outcome: Result<[ExtensionItem], Error>?
        manager.runItems(ext, query: "fictional-secret-query", fetch: { requests, _, reply in
            reply(requests.map { .init(url: $0.url.absoluteString, status: 200, body: "{}") })
        }) { outcome = $0 }
        XCTAssertEqual(try XCTUnwrap(outcome).get().count, 1)
        let events = recorder.log.events(for: ext.id)
        XCTAssertEqual(summary(events), ["clipboardRead completed", "module completed plan", "fetch completed news.example.com",
                                         "module completed render", "storageSave completed"])
        XCTAssertEqual(Set(events.map(\.invocation)).count, 1, "One run, one invocation")
        XCTAssertTrue(events.allSatisfy { $0.version == "2" && $0.codeHash == ext.manifest.sha256 })
        XCTAssertNotNil(events.first { $0.operation == .fetch }?.duration)
        let recorded = events.map { "\($0.detail ?? "")" }.joined()
        for secret in ["fictional-secret-query", "search", "clipboard secret", "Private row"] {
            XCTAssertFalse(recorded.contains(secret), "Activity must not record \(secret)")
        }
    }

    func testACancelledRunRecordsTheCancelledFetchAndNoRender() throws {
        let (manager, ext) = try manager()
        manager.cancelFetches = {}
        script(manager, [#"{"fetch":["https://news.example.com/slow"]}"#])
        var pending: (([ExtensionNetwork.Response]) -> Void)?
        manager.runItems(ext, query: "", fetch: { _, _, reply in pending = reply }) { _ in }
        manager.cancelItemsRun()
        try XCTUnwrap(pending)([.init(url: "https://news.example.com/slow", status: 0, body: "")])
        XCTAssertEqual(summary(recorder.log.events(for: ext.id)), ["clipboardRead completed", "module completed plan", "fetch cancelled news.example.com"])
    }

    func testARefusedURLIsRecordedAsADeniedRequestToItsHostOnly() throws {
        let (manager, ext) = try manager()
        script(manager, [#"{"fetch":["https://tracker.example.net/collect?id=fictional"]}"#])
        manager.runItems(ext, query: "", fetch: { _, _, _ in XCTFail("A refused URL is never fetched") }) { _ in }
        XCTAssertEqual(summary(recorder.log.events(for: ext.id)).last, "fetch denied tracker.example.net")
    }

    func testADisabledExtensionsModuleCallIsDenied() throws {
        let (manager, ext) = try manager(enabled: false)
        var outcome: Result<ExtensionManager.TextOutcome, Error>?
        manager.runText(ext, input: "") { outcome = $0 }
        guard case .failure = try XCTUnwrap(outcome) else { return XCTFail("A disabled extension must not run") }
        XCTAssertEqual(summary(recorder.log.events(for: ext.id)), ["module denied run"])
    }

    func testAStoppedHelperPastItsTimeLimitTimedOut() {
        let stopped = Result<String, Error>.failure(ExtensionManager.ExtensionError.stopped)
        XCTAssertEqual(ExtensionManager.outcome(of: stopped, duration: 2.1, timeout: 2), .timedOut, "The watchdog stops a runaway at its limit")
        XCTAssertEqual(ExtensionManager.outcome(of: stopped, duration: 0.3, timeout: 2), .failed, "Stopping early is a failure, not a timeout")
        XCTAssertEqual(ExtensionManager.outcome(of: .failure(ExtensionManager.ExtensionError.timedOut), duration: 3, timeout: 2), .timedOut)
        XCTAssertEqual(ExtensionManager.outcome(of: .failure(ExtensionManager.ExtensionError.revoked("Reader", nil)), duration: 0, timeout: 2), .denied)
        XCTAssertEqual(ExtensionManager.outcome(of: .success("ok"), duration: 0, timeout: 2), .completed)
    }

    func testTheRecorderKeepsTheNewestEventsAndCountsWhatItDropped() {
        let small = ExtensionActivityRecorder(capacity: 2)
        for invocation in 1...3 {
            small.record(ExtensionActivity(extensionID: "fixture", version: "1", codeHash: "", invocation: invocation, time: Date(),
                                           operation: .module, outcome: .completed))
        }
        XCTAssertEqual(small.log.events.map(\.invocation), [2, 3])
        XCTAssertEqual(small.log.dropped, 1)
        small.clear()
        XCTAssertEqual(small.log.events.count, 0)
        XCTAssertEqual(small.log.dropped, 0)
    }
}
