import VolantCore
import XCTest
import AppKit
import CryptoKit
@testable import Volant

final class SearchRecoveryTests: XCTestCase {
    @MainActor
    func testAppIndexRefusalPreservesResultsAndRetriesWithoutDuplicateStart() {
        var allowed = false
        var attempts = 0
        let entry = AppEntry(id: "fixture", name: "Fixture", url: URL(fileURLWithPath: "/Applications/Fixture.app"), lastUsed: nil)
        let index = AppIndex(entries: [entry], startQuery: { _ in attempts += 1; return allowed })
        index.start()
        XCTAssertTrue(index.unavailable)
        XCTAssertEqual(index.search("Fixture"), [entry])
        allowed = true
        index.start(); index.start()
        XCTAssertFalse(index.unavailable)
        XCTAssertEqual(attempts, 2)
    }

    @MainActor
    func testFileRefusalCompletesOnceReleasesCallbackAndCanRetry() async {
        var attempts = 0
        let files = FileSearch(startQuery: { _ in attempts += 1; return false })
        final class Lifetime {}
        var lifetime: Lifetime? = Lifetime()
        weak var released = lifetime
        let first = expectation(description: "first refusal")
        files.search("fictional") { [retained = lifetime] result in
            XCTAssertNotNil(retained)
            if case .success = result { XCTFail("Refusal is not an empty result") }
            first.fulfill()
        }
        lifetime = nil
        await fulfillment(of: [first], timeout: 2)
        XCTAssertNil(released, "Failure must release the completion, including its debounce work item")
        let second = expectation(description: "retry refusal")
        files.search("fictional") { result in
            if case .success = result { XCTFail("Refusal is not an empty result") }
            second.fulfill()
        }
        await fulfillment(of: [second], timeout: 2)
        XCTAssertEqual(attempts, 2)
        let cancelled = expectation(description: "cancelled callback")
        cancelled.isInverted = true
        files.search("cancelled") { _ in cancelled.fulfill() }
        files.cancel()
        await fulfillment(of: [cancelled], timeout: 0.25)
        XCTAssertEqual(attempts, 2)
    }

    @MainActor
    func testOldFileQueryCannotCompleteAfterNewSearch() async {
        var queries: [NSMetadataQuery] = []
        let files = FileSearch(startQuery: { queries.append($0); return true })
        let old = expectation(description: "obsolete query")
        old.isInverted = true
        files.search("first") { _ in old.fulfill() }
        try? await Task.sleep(for: .milliseconds(200))
        XCTAssertEqual(queries.count, 1)
        files.search("second") { _ in }
        if let query = queries.first {
            NotificationCenter.default.post(name: .NSMetadataQueryDidFinishGathering, object: query)
        }
        await fulfillment(of: [old], timeout: 0.25)
        files.cancel()
    }

    @MainActor
    func testLauncherFailureIsVisibleWithRowsAndScopedToCurrentQuery() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        var allowed = false
        let index = AppIndex(startQuery: { _ in allowed })
        index.start()
        let model = LauncherModel(index: index,
            clipboard: ClipboardStore(retention: 10, storageURL: root.appendingPathComponent("clips.sqlite"), encryptionKey: SymmetricKey(size: .bits256)),
            notes: NotesStore(directory: root.appendingPathComponent("Notes")), config: Preferences(),
            usage: UsageStore(url: root.appendingPathComponent("usage.sqlite")), files: FileSearch(startQuery: { _ in false })) { _ in }
        model.searchesSecondarySources = false
        model.query = "fixture"
        XCTAssertNotNil(model.searchRecoveryMessage)
        allowed = true
        model.retrySearch()
        XCTAssertNil(model.searchRecoveryMessage)
        model.query = "/fictional"
        try await Task.sleep(for: .milliseconds(250))
        XCTAssertTrue(model.filesUnavailable)
        XCTAssertNotNil(model.searchRecoveryMessage)
        model.query = "clip"
        XCTAssertNil(model.searchRecoveryMessage)
        model.query = "/other"
        model.query = "clip"
        try await Task.sleep(for: .milliseconds(250))
        XCTAssertFalse(model.filesUnavailable)
        XCTAssertNil(model.searchRecoveryMessage)
    }

    func testUnreadableNoteKeepsIdentityPinAndBytesUntilRepaired() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let store = NotesStore(directory: root)
        defer {
            try? FileManager.default.removeItem(at: root)
            UserDefaults.standard.removeObject(forKey: "notes." + root.path + ".selected")
            UserDefaults.standard.removeObject(forKey: "notes." + root.path + ".pinned")
        }
        let note = store.create(initialText: "Fictional reference")
        let model = NotesModel(store: store)
        model.select(note.id); model.togglePin()
        let invalid = Data([0xFF, 0xFE, 0xFA])
        try invalid.write(to: note.url)
        store.reload()
        XCTAssertNotNil(store.loadMessage)
        XCTAssertEqual(store.notes.first?.id, note.id)
        XCTAssertEqual(store.notes.first?.title, note.id)
        XCTAssertNotNil(model.selected?.readError)
        XCTAssertTrue(model.pinned.contains(note.id))
        XCTAssertEqual(store.search(note.id).count, 1)
        store.update(note.id, text: "Must not overwrite unreadable bytes")
        store.flush(); model.deleteSelected()
        XCTAssertEqual(try Data(contentsOf: note.url), invalid)
        XCTAssertTrue(model.pinned.contains(note.id))
        try "Repaired UTF-8".write(to: note.url, atomically: true, encoding: .utf8)
        store.reload()
        XCTAssertNil(store.loadMessage)
        XCTAssertNil(model.selected?.readError)
        XCTAssertEqual(model.selected?.text, "Repaired UTF-8")
        XCTAssertEqual(model.selectedID, note.id)
    }

    func testDirectoryFailureKeepsNotesAndDirtyEditsAndRecovers() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let store = NotesStore(directory: root)
        defer { try? FileManager.default.removeItem(at: root) }
        let note = store.create(initialText: "Original")
        store.update(note.id, text: "Unsaved draft")
        try FileManager.default.removeItem(at: root)
        store.reload()
        XCTAssertNotNil(store.loadError)
        XCTAssertEqual(store.notes.first?.text, "Unsaved draft")
        XCTAssertEqual(store.dirtyText[note.id], "Unsaved draft")
        store.flush()
        XCTAssertNotNil(store.saveErrors[note.id])
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        store.reload()
        XCTAssertNil(store.loadError)
        XCTAssertEqual(store.notes.first?.id, note.id)
        store.flush()
        XCTAssertEqual(try String(contentsOf: note.url, encoding: .utf8), "Unsaved draft")
    }
}
