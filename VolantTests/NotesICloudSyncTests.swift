import XCTest
import VolantCore
@testable import Volant

/// Notes sync against temporary folders standing in for the local notes folder and the iCloud
/// container; no test reaches the owner's iCloud, notes or a metadata query.
final class NotesICloudSyncTests: XCTestCase {
    private var root: URL!
    private var local: URL!
    private var container: URL!
    private var cloud: URL { NotesLocation.cloudFolder(in: container) }
    private var defaults: UserDefaults!
    private var suiteName: String!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("volant-notes-sync-\(UUID().uuidString)", isDirectory: true)
        local = root.appendingPathComponent("Support/Notes", isDirectory: true)
        container = root.appendingPathComponent("Container", isDirectory: true)
        try FileManager.default.createDirectory(at: local, withIntermediateDirectories: true)
        suiteName = "NotesICloudSyncTests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDownWithError() throws {
        defaults.removePersistentDomain(forName: suiteName)
        try? FileManager.default.removeItem(at: root)
    }

    func testCopyKeepsNewerDestinationAndReplacesOlder() throws {
        let source = root.appendingPathComponent("A"), destination = root.appendingPathComponent("B")
        try write("fresh", "kept.md", in: source, at: Date(timeIntervalSince1970: 1_000))
        try write("newer elsewhere", "kept.md", in: destination, at: Date(timeIntervalSince1970: 2_000))
        try write("updated", "replaced.md", in: source, at: Date(timeIntervalSince1970: 2_000))
        try write("stale", "replaced.md", in: destination, at: Date(timeIntervalSince1970: 1_000))
        try write("not a note", "image.png", in: source)

        XCTAssertEqual(NotesLocation.copyNotes(from: source, to: destination), 0)
        XCTAssertEqual(try read("kept.md", in: destination), "newer elsewhere")
        XCTAssertEqual(try read("replaced.md", in: destination), "updated")
        XCTAssertFalse(FileManager.default.fileExists(atPath: destination.appendingPathComponent("image.png").path))
    }

    func testSetAsideRenamesOnlyAFolderWithContents() throws {
        XCTAssertNil(NotesLocation.setAside(local))
        try write("# Fictional", "a.md", in: local)
        let backup = try XCTUnwrap(NotesLocation.setAside(local))
        XCTAssertTrue(backup.lastPathComponent.hasPrefix("Notes before iCloud "))
        XCTAssertEqual(try read("a.md", in: backup), "# Fictional")
        XCTAssertFalse(FileManager.default.fileExists(atPath: local.path))
    }

    func testTurningOnMovesNotesPinsAndStoreToICloud() throws {
        try write("# Fictional trip\nBig Sur", "2026-11-01-aaaa.md", in: local)
        let store = NotesStore(directory: local)
        defaults.set(["2026-11-01-aaaa.md"], forKey: "notes." + local.path + ".pinned")
        let sync = makeSync(store)

        try waitForStatus(sync, .on) { sync.update(enabled: true) }

        XCTAssertEqual(store.directory, cloud)
        XCTAssertEqual(store.notes.map(\.title), ["Fictional trip"])
        XCTAssertEqual(try read("2026-11-01-aaaa.md", in: cloud), "# Fictional trip\nBig Sur")
        XCTAssertEqual(defaults.stringArray(forKey: "notes." + cloud.path + ".pinned"), ["2026-11-01-aaaa.md"])
        XCTAssertFalse(FileManager.default.fileExists(atPath: local.path), "the local folder is set aside as a backup")
        let backups = try FileManager.default.contentsOfDirectory(atPath: local.deletingLastPathComponent().path)
        XCTAssertTrue(backups.contains { $0.hasPrefix("Notes before iCloud ") })
        XCTAssertEqual(NotesLocation.current, cloud)
        NotesLocation.current = NotesLocation.local
    }

    func testTurningOffCopiesICloudNotesBackToThisMac() throws {
        let store = NotesStore(directory: local)
        let sync = makeSync(store)
        try waitForStatus(sync, .on) { sync.update(enabled: true) }
        let note = store.create(initialText: "# Written while syncing")
        store.flush()

        try waitForStatus(sync, .off) { sync.update(enabled: false) }

        XCTAssertEqual(store.directory, local)
        XCTAssertEqual(try read(note.id, in: local), "# Written while syncing")
        XCTAssertEqual(try read(note.id, in: cloud), "# Written while syncing", "iCloud keeps its copy for other devices")
        XCTAssertFalse(defaults.bool(forKey: "notes.iCloudActive"))
        NotesLocation.current = NotesLocation.local
    }

    func testTurningOffOnAMacThatNeverSyncedLeavesNotesAlone() throws {
        try write("# Local only", "a.md", in: local)
        let store = NotesStore(directory: local)
        let sync = makeSync(store)
        sync.update(enabled: false)
        XCTAssertEqual(sync.status, .off)
        XCTAssertEqual(store.directory, local)
        XCTAssertFalse(FileManager.default.fileExists(atPath: cloud.path))
    }

    func testUnavailableICloudKeepsNotesLocal() throws {
        try write("# Local only", "a.md", in: local)
        let store = NotesStore(directory: local)
        let sync = NotesICloudSync(store: store, defaults: defaults, localFolder: local, resolveContainer: { nil }, makeWatcher: { _, _ in nil })

        try waitForStatus(sync, .unavailable) { sync.update(enabled: true) }

        XCTAssertEqual(store.directory, local)
        XCTAssertEqual(try read("a.md", in: local), "# Local only")
    }

    func testRelocateRefusesWhileASaveIsFailing() throws {
        let store = NotesStore(directory: local)
        try FileManager.default.removeItem(at: local)
        let note = store.create(initialText: "Fictional draft")
        XCTAssertNotNil(store.saveErrors[note.id])

        XCTAssertFalse(store.relocate(to: cloud))
        XCTAssertEqual(store.directory, local)
        XCTAssertEqual(store.dirtyText[note.id], "Fictional draft")
    }

    func testNoteNotYetDownloadedIsListedButNeverReadOrEdited() throws {
        try write("# Here", "a.md", in: local)
        try write("", ".b.md.icloud", in: local)
        let store = NotesStore(directory: local, searchReader: { url in
            XCTAssertNotEqual(url.lastPathComponent, "b.md", "a note still in iCloud must not be read")
            return try? String(contentsOf: url, encoding: .utf8)
        })
        let pending = try XCTUnwrap(store.notes.first { $0.id == "b.md" })
        XCTAssertTrue(pending.downloading)
        XCTAssertNil(pending.readError)

        store.open("b.md")
        XCTAssertNil(store.notes.first { $0.id == "b.md" }?.text)
        XCTAssertNil(store.text(of: "b.md"))
        store.update("b.md", text: "typed before it arrived")
        XCTAssertNil(store.dirtyText["b.md"], "edits wait until the note has downloaded")
        let searched = expectation(description: "full-text search finishes without reading the pending note")
        store.searchFiles("Here") { found in
            XCTAssertEqual(found.map(\.id), ["a.md"])
            searched.fulfill()
        }
        wait(for: [searched], timeout: 5)

        try FileManager.default.removeItem(at: local.appendingPathComponent(".b.md.icloud"))
        try write("# Arrived\nfrom another device", "b.md", in: local)
        store.reload()
        store.open("b.md")
        let arrived = try XCTUnwrap(store.notes.first { $0.id == "b.md" })
        XCTAssertFalse(arrived.downloading)
        XCTAssertEqual(arrived.title, "Arrived")
        XCTAssertEqual(store.text(of: "b.md"), "# Arrived\nfrom another device")
    }

    private func makeSync(_ store: NotesStore) -> NotesICloudSync {
        let container = container!
        return NotesICloudSync(store: store, defaults: defaults, localFolder: local, resolveContainer: { container }, makeWatcher: { _, _ in nil })
    }

    private func waitForStatus(_ sync: NotesICloudSync, _ expected: NotesICloudSync.Status, after action: () -> Void) throws {
        let reached = expectation(description: "status \(expected)")
        reached.assertForOverFulfill = false
        sync.onStatus = { if $0 == expected { reached.fulfill() } }
        action()
        if sync.status == expected { reached.fulfill() }
        wait(for: [reached], timeout: 5)
        sync.onStatus = { _ in }
    }

    private func write(_ text: String, _ name: String, in folder: URL, at date: Date? = nil) throws {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = folder.appendingPathComponent(name)
        try text.write(to: url, atomically: true, encoding: .utf8)
        if let date { try FileManager.default.setAttributes([.modificationDate: date], ofItemAtPath: url.path) }
    }

    private func read(_ name: String, in folder: URL) throws -> String {
        try String(contentsOf: folder.appendingPathComponent(name), encoding: .utf8)
    }
}
