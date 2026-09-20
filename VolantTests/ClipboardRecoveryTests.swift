import XCTest
import CryptoKit
import Security
import SQLite3
@testable import Volant

final class ClipboardRecoveryTests: XCTestCase {
    private func temporary() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        return root
    }
    private func waitFor(_ condition: () -> Bool) {
        let deadline = Date().addingTimeInterval(3)
        while !condition() && Date() < deadline { RunLoop.main.run(until: Date().addingTimeInterval(0.01)) }
        XCTAssertTrue(condition())
    }
    func testKeyReadFailuresNeverCreateOrReplaceKeys() throws {
        for status in [errSecInteractionNotAllowed, errSecUserCanceled, errSecAuthFailed] {
            var adds = 0
            XCTAssertThrowsError(try KeychainKey.load(createIfMissing: true, access: .init(read: { (status, nil) }, add: { _ in adds += 1; return errSecSuccess }))) {
                XCTAssertEqual($0 as? KeychainKey.Failure, .access(status))
            }
            XCTAssertEqual(adds, 0)
        }
        var adds = 0
        XCTAssertThrowsError(try KeychainKey.load(createIfMissing: false, access: .init(read: { (errSecItemNotFound, nil) }, add: { _ in adds += 1; return errSecSuccess }))) {
            XCTAssertEqual($0 as? KeychainKey.Failure, .missingHistoryKey)
        }
        XCTAssertThrowsError(try KeychainKey.load(createIfMissing: true, access: .init(read: { (errSecSuccess, Data([1])) }, add: { _ in adds += 1; return errSecSuccess }))) {
            XCTAssertEqual($0 as? KeychainKey.Failure, .invalidKey)
        }
        XCTAssertEqual(adds, 0)
    }
    func testFirstCreationAndDuplicateRaceUsePersistedKey() throws {
        var saved: Data?
        let created = try KeychainKey.load(createIfMissing: true, access: .init(read: { (errSecItemNotFound, nil) }, add: { saved = $0; return errSecSuccess }))
        XCTAssertEqual(created.withUnsafeBytes { Data($0) }, saved)
        var reads = 0
        let winner = Data(repeating: 7, count: 32)
        let key = try KeychainKey.load(createIfMissing: true, access: .init(read: {
            reads += 1
            return reads == 1 ? (errSecItemNotFound, nil) : (errSecSuccess, winner)
        }, add: { _ in errSecDuplicateItem }))
        XCTAssertEqual(key.withUnsafeBytes { Data($0) }, winner)
        XCTAssertThrowsError(try KeychainKey.load(createIfMissing: true, access: .init(read: { (errSecItemNotFound, nil) }, add: { _ in errSecAuthFailed })))
    }
    func testUnavailableKeyRecoversAndPreservesEncryptedHistory() throws {
        let root = try temporary(), url = root.appendingPathComponent("clipboard.sqlite")
        let key = SymmetricKey(size: .bits256)
        do {
            let original = ClipboardStore(retention: 10, storageURL: url, encryptionKey: key)
            original.record("fictional saved text")
            XCTAssertEqual(original.recent().count, 1)
        }
        var available = false
        var creationChoices: [Bool] = []
        let store = ClipboardStore(retention: 10, storageURL: url, keyLoader: { create in
            creationChoices.append(create)
            guard available else { throw KeychainKey.Failure.access(errSecInteractionNotAllowed) }
            return key
        })
        XCTAssertEqual(store.state, .unavailable(.key(.access(errSecInteractionNotAllowed))))
        store.record("missed copy must not be replayed")
        XCTAssertTrue(store.recent().isEmpty)
        available = true
        store.retry(); waitFor { store.state == .ready }
        XCTAssertEqual(store.recent().map(\.text), ["fictional saved text"])
        XCTAssertEqual(creationChoices, [false, false])
        store.record("new fictional copy")
        XCTAssertEqual(store.recent().count, 2)
        let data = try Data(contentsOf: url)
        XCTAssertNil(data.range(of: Data("fictional saved text".utf8)))
        XCTAssertNil(data.range(of: Data("new fictional copy".utf8)))
    }
    func testDatabaseOpenFailureRecoversWithoutTouchingKey() throws {
        let root = try temporary(), parent = root.appendingPathComponent("missing")
        var loads = 0
        let store = ClipboardStore(retention: 10, storageURL: parent.appendingPathComponent("clipboard.sqlite"), keyLoader: { _ in loads += 1; return SymmetricKey(size: .bits256) })
        XCTAssertEqual(store.state, .unavailable(.database)); XCTAssertEqual(loads, 0)
        try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
        store.retry(); waitFor { store.state == .ready }
        store.record("recovered")
        XCTAssertEqual(store.recent().map(\.text), ["recovered"])
        XCTAssertEqual(loads, 1)
    }
    func testWriteFailureIsVisibleAndRetryPreservesRows() throws {
        let root = try temporary(), url = root.appendingPathComponent("clipboard.sqlite")
        let store = ClipboardStore(retention: 10, storageURL: url, encryptionKey: SymmetricKey(size: .bits256))
        store.record("retained"); XCTAssertEqual(store.recent().count, 1)
        var other: OpaquePointer?
        XCTAssertEqual(sqlite3_open(url.path, &other), SQLITE_OK)
        defer { sqlite3_close(other) }
        XCTAssertEqual(sqlite3_exec(other, "BEGIN IMMEDIATE", nil, nil, nil), SQLITE_OK)
        store.record("blocked")
        _ = store.recent()
        XCTAssertEqual(store.state, .unavailable(.database))
        XCTAssertEqual(sqlite3_exec(other, "ROLLBACK", nil, nil, nil), SQLITE_OK)
        store.retry(); waitFor { store.state == .ready }
        XCTAssertEqual(store.recent().map(\.text), ["retained"])
    }
    func testUnreadableRowsArePreservedAndReported() throws {
        let root = try temporary(), url = root.appendingPathComponent("clipboard.sqlite")
        let key = SymmetricKey(size: .bits256)
        do {
            let store = ClipboardStore(retention: 10, storageURL: url, encryptionKey: key)
            store.record("original"); XCTAssertEqual(store.recent().count, 1)
        }
        let wrong = ClipboardStore(retention: 10, storageURL: url, encryptionKey: SymmetricKey(size: .bits256))
        XCTAssertTrue(wrong.recent().isEmpty)
        XCTAssertEqual(wrong.state, .unavailable(.unreadableEntries))
        wrong.record("do not trim or write while unreadable"); _ = wrong.recent()
        let restored = ClipboardStore(retention: 10, storageURL: url, encryptionKey: key)
        XCTAssertEqual(restored.recent().map(\.text), ["original"])
    }
    func testLegacySchemaMigratesWithoutReplacingHistoryOrKey() throws {
        let root = try temporary(), url = root.appendingPathComponent("clipboard.sqlite")
        let key = SymmetricKey(size: .bits256)
        let sealed = try AES.GCM.seal(Data("legacy fictional row".utf8), using: key).combined!
        let hex = sealed.map { String(format: "%02x", $0) }.joined()
        var db: OpaquePointer?
        XCTAssertEqual(sqlite3_open(url.path, &db), SQLITE_OK)
        let sql = "CREATE TABLE clips (id INTEGER PRIMARY KEY AUTOINCREMENT, hash TEXT UNIQUE, blob BLOB NOT NULL, copied_at REAL NOT NULL); INSERT INTO clips(hash,blob,copied_at) VALUES ('fixture',X'\(hex)',1)"
        XCTAssertEqual(sqlite3_exec(db, sql, nil, nil, nil), SQLITE_OK)
        sqlite3_close(db)
        var allowCreation = true
        let store = ClipboardStore(retention: 10, storageURL: url, keyLoader: { allowCreation = $0; return key })
        XCTAssertFalse(allowCreation)
        XCTAssertEqual(store.state, .ready)
        XCTAssertEqual(store.recent().map(\.text), ["legacy fictional row"])
        store.retry(); waitFor { store.state == .ready }
        XCTAssertFalse(allowCreation)
        XCTAssertEqual(store.recent().count, 1)
    }
    func testRetryDeduplicatesAndDoesNotReplaceAnotherLauncherQuery() throws {
        let root = try temporary(), key = SymmetricKey(size: .bits256)
        let entered = DispatchSemaphore(value: 0), release = DispatchSemaphore(value: 0)
        var attempts = 0
        let store = ClipboardStore(retention: 10, storageURL: root.appendingPathComponent("clipboard.sqlite"), keyLoader: { _ in
            attempts += 1
            if attempts == 1 { throw KeychainKey.Failure.access(errSecUserCanceled) }
            entered.signal(); _ = release.wait(timeout: .now() + 2)
            return key
        })
        let model = LauncherModel(index: AppIndex(entries: []), clipboard: store, notes: NotesStore(directory: root.appendingPathComponent("Notes")), config: Preferences(), usage: UsageStore(url: root.appendingPathComponent("usage.sqlite"))) { _ in }
        model.searchesSecondarySources = false; model.query = "clip"
        XCTAssertNotNil(model.clipboardMessage)
        model.retryClipboard(); XCTAssertEqual(entered.wait(timeout: .now() + 1), .success)
        store.retry(); XCTAssertTrue(model.clipboardRetrying)
        model.query = "2 + 2"
        let ids = model.rows.map(\.id)
        release.signal(); waitFor { store.state == .ready }
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        XCTAssertEqual(attempts, 2); XCTAssertEqual(model.rows.map(\.id), ids)
        XCTAssertNil(model.clipboardMessage)
        store.record("alpha"); store.record("beta")
        model.query = "clip   alpha"
        XCTAssertEqual(model.rows.count, 1)
        XCTAssertEqual(model.rows.first?.id, "clip:1")
    }
}
