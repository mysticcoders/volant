import AppKit
import CryptoKit
import VolantCore
import XCTest
@testable import Volant

/// File search with the optional fsearch integration, using a fake helper call instead of XPC and a
/// refused Spotlight start instead of real queries. Paths are fictional.
@MainActor
final class FSearchFileSearchTests: XCTestCase {
    private func client(_ answer: @escaping (FSearchClient.Request) -> (Data?, String?), requests: ((FSearchClient.Request) -> Void)? = nil) -> FSearchClient {
        let client = FSearchClient()
        client.call = { request, completion in
            requests?(request)
            let (data, error) = answer(request)
            DispatchQueue.main.async { completion(data, error) }
        }
        return client
    }

    private func hits(_ paths: [String]) -> Data {
        try! JSONEncoder().encode(paths.map { FSearch.Hit(path: $0, kind: $0.hasSuffix("/") ? "dir" : "file") })
    }

    private func search(_ files: FileSearch, _ term: String) async -> FileSearch.SearchResult {
        await withCheckedContinuation { continuation in files.search(term) { continuation.resume(returning: $0) } }
    }

    func testFSearchAnswersWithoutSpotlightAndHidesNoise() async {
        var spotlightStarted = false
        let files = FileSearch(startQuery: { _ in spotlightStarted = true; return false })
        files.fsearch = client({ _ in (self.hits(["/Users/me/Projects/main.rs", "/Users/me/Library/Caches/main.rs", "/Users/me/app/build/main.rs",
                                                 "/Users/me/.hidden/main.rs"] + (0..<12).map { "/Users/me/n\($0)/main.rs" }), nil) })
        guard case .success(let entries) = await search(files, "mian.rs") else { return XCTFail("Expected results") }
        XCTAssertFalse(spotlightStarted, "fsearch answered, so Spotlight never ran")
        XCTAssertEqual(entries.first?.url.path, "/Users/me/Projects/main.rs")
        XCTAssertFalse(entries.contains { $0.url.path.contains("/Library/") || $0.url.path.contains("/build/") || $0.url.path.contains("/.hidden/") })
        XCTAssertEqual(entries.count, 8, "At most eight file rows")
    }

    func testAnUnreachableDaemonFallsBackToSpotlight() async {
        var spotlightStarted = false
        let files = FileSearch(startQuery: { _ in spotlightStarted = true; return false })
        files.fsearch = client({ _ in (nil, FSearchError.notRunning.localizedDescription) })
        guard case .failure(.unavailable) = await search(files, "invoice") else { return XCTFail("Expected Spotlight's answer") }
        XCTAssertTrue(spotlightStarted, "The same term went to Spotlight")
    }

    func testOnlyTheNewestQueryIsAnswered() async {
        var pending: [(Data?, String?) -> Void] = []
        let files = FileSearch(startQuery: { _ in false })
        let fake = FSearchClient()
        fake.call = { _, completion in pending.append(completion) }
        files.fsearch = fake
        var answers: [String] = []
        files.search("old") { if case .success(let e) = $0 { answers.append("old:\(e.count)") } }
        try? await Task.sleep(nanoseconds: 120_000_000)
        files.search("new") { if case .success(let e) = $0 { answers.append("new:\(e.count)") } }
        try? await Task.sleep(nanoseconds: 120_000_000)
        XCTAssertEqual(pending.count, 2)
        pending[1](hits(["/Users/me/new.txt"]), nil)
        pending[0](hits(["/Users/me/old.txt"]), nil)
        try? await Task.sleep(nanoseconds: 50_000_000)
        XCTAssertEqual(answers, ["new:1"], "A late answer to an old query is dropped")
    }

    func testSettingTurnsFSearchOnAndOpeningReportsTheFile() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        var config = Preferences()
        let model = LauncherModel(index: AppIndex(entries: []),
            clipboard: ClipboardStore(retention: 10, storageURL: root.appendingPathComponent("clips.sqlite"), encryptionKey: SymmetricKey(size: .bits256)),
            notes: NotesStore(directory: root.appendingPathComponent("Notes")), config: config,
            usage: UsageStore(url: root.appendingPathComponent("usage.sqlite")), files: FileSearch(startQuery: { _ in false }), onNote: { _ in })
        XCTAssertNil(model.files.fsearch, "Off by default")
        var opened: [String] = []
        model.fsearchClient = client({ _ in (nil, nil) }) { if case .opened(let path) = $0 { opened.append(path) } }
        config.fileSearchUsesFSearch = true
        model.config = config
        XCTAssertTrue(model.files.fsearch === model.fsearchClient)
        config.fileSearchUsesFSearch = false
        model.config = config
        XCTAssertNil(model.files.fsearch)
        XCTAssertTrue(opened.isEmpty)
    }
}
