import Foundation
import SQLite3
import CryptoKit
import Combine
import VolantCore

struct ClipEntry: Identifiable, Hashable {
    enum Kind: Int { case text = 0, image = 1 }
    let id: Int64
    let kind: Kind
    let text: String
    let copiedAt: Date
    let imageData: Data?
}

/// Text clipboard history in SQLite, each entry AES-GCM encrypted with a Keychain key, excluded from backups,
/// with secure_delete on so removed rows are overwritten rather than left in free pages.
final class ClipboardStore {
    enum Failure: Equatable {
        case key(KeychainKey.Failure)
        case database
        case unreadableEntries
        var message: String {
            switch self {
            case .key(.missingHistoryKey): return "Clipboard history’s encryption key is missing. Existing history has been preserved. Restore access to its original Keychain key, then retry."
            case .key(.invalidKey): return "Clipboard history’s encryption key couldn’t be read. Existing history has been preserved. Check Keychain access, then retry."
            case .key: return "Clipboard history can’t access its encryption key. Unlock your login Keychain or allow access, then retry."
            case .database: return "Clipboard history’s storage is unavailable. Check available disk space and access, then retry."
            case .unreadableEntries: return "Some clipboard items couldn’t be read. Existing history has been preserved. Check access to its original Keychain key, then retry."
            }
        }
    }
    enum State: Equatable {
        case ready, retrying, unavailable(Failure)
        var message: String? {
            switch self {
            case .ready: return nil
            case .retrying: return "Retrying clipboard history…"
            case .unavailable(let failure): return failure.message + " New copies aren’t being saved."
            }
        }
    }
    let changes = PassthroughSubject<Void, Never>()
    private let stateLock = NSLock()
    private var currentState = State.ready
    var state: State { stateLock.withLock { currentState } }
    private var db: OpaquePointer?
    private var key: SymmetricKey?
    private var failure: Failure?
    private let storageURL: URL
    private let loadKey: (Bool) throws -> SymmetricKey
    var retention: Int { didSet { queue.async { self.trim() } } }
    private let queue = DispatchQueue(label: "com.mysticcoders.volant.clipboard")
    /// One decrypted entry kept for an open search. Images keep only their size; their bytes are
    /// decrypted again for the few that match.
    private struct SearchEntry {
        let id: Int64
        let kind: ClipEntry.Kind
        let text: String
        let copiedAt: Date
        let byteCount: Int
    }
    private let searchLock = NSLock()
    private var searchEntries: [SearchEntry]?

    init(retention: Int, storageURL: URL? = nil, encryptionKey: SymmetricKey? = nil,
         keyLoader: ((Bool) throws -> SymmetricKey)? = nil) {
        self.retention = max(10, retention)
        self.storageURL = storageURL ?? Preferences.supportDirectory.appendingPathComponent("clipboard.sqlite")
        self.loadKey = keyLoader ?? { create in
            if let encryptionKey { return encryptionKey }
            return try KeychainKey.load(createIfMissing: create)
        }
        queue.sync { recover() }
    }

    /// Retry on the storage queue, after earlier writes. Never replay missed clipboard captures.
    func retry() {
        let started = stateLock.withLock {
            guard currentState != .retrying else { return false }
            currentState = .retrying
            return true
        }
        guard started else { return }
        changes.send()
        queue.async { self.recover() }
    }

    private func setState(_ state: State) {
        let changed = stateLock.withLock {
            guard currentState != state else { return false }
            currentState = state
            return true
        }
        if changed { changes.send() }
    }
    private func fail(_ error: Failure) {
        failure = error
        if state != .retrying { setState(.unavailable(error)) }
    }
    private func recover() {
        invalidateSearch()
        sqlite3_close(db); db = nil; key = nil; failure = nil
        do {
            guard sqlite3_open(storageURL.path, &db) == SQLITE_OK,
                  execute("PRAGMA secure_delete = ON"), execute("PRAGMA journal_mode = DELETE"),
                  execute("CREATE TABLE IF NOT EXISTS clips (id INTEGER PRIMARY KEY AUTOINCREMENT, hash TEXT UNIQUE, blob BLOB NOT NULL, copied_at REAL NOT NULL, kind INTEGER NOT NULL DEFAULT 0)"),
                  execute("CREATE INDEX IF NOT EXISTS clips_copied_at ON clips (copied_at DESC)") else { throw FailureError.database }
            var probe: OpaquePointer?
            if sqlite3_prepare_v2(db, "SELECT kind FROM clips LIMIT 0", -1, &probe, nil) != SQLITE_OK {
                sqlite3_finalize(probe); probe = nil
                guard execute("ALTER TABLE clips ADD COLUMN kind INTEGER NOT NULL DEFAULT 0") else { throw FailureError.database }
            }
            sqlite3_finalize(probe)
            var count: OpaquePointer?
            guard sqlite3_prepare_v2(db, "SELECT EXISTS(SELECT 1 FROM clips)", -1, &count, nil) == SQLITE_OK else { throw FailureError.database }
            defer { sqlite3_finalize(count) }
            guard sqlite3_step(count) == SQLITE_ROW else { throw FailureError.database }
            key = try loadKey(sqlite3_column_int(count, 0) == 0)
            excludeFromBackup(storageURL)
            setState(.ready)
        } catch let error as KeychainKey.Failure {
            failure = .key(error); setState(.unavailable(.key(error)))
        } catch {
            failure = .database; setState(.unavailable(.database))
        }
    }
    private enum FailureError: Error { case database }

    deinit { sqlite3_close(db) }

    func record(_ text: String) { store(Data(text.utf8), kind: .text) }

    /// Images are stored as PNG bytes, encrypted exactly like text.
    func recordImage(_ png: Data) { store(png, kind: .image) }

    private func store(_ payload: Data, kind: ClipEntry.Kind) {
        guard state == .ready else { return }
        queue.async {
            guard self.failure == nil, let key = self.key, let db = self.db else { return }
            let hash = ClipboardStore.fingerprint(payload, key: key)
            guard let sealed = try? AES.GCM.seal(payload, using: key), let combined = sealed.combined else { self.fail(.unreadableEntries); return }
            var stmt: OpaquePointer?
            let sql = "INSERT INTO clips (hash, blob, copied_at, kind) VALUES (?, ?, ?, ?) ON CONFLICT(hash) DO UPDATE SET copied_at = excluded.copied_at"
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { self.fail(.database); return }
            defer { sqlite3_finalize(stmt) }
            sqlite3_bind_text(stmt, 1, hash, -1, ClipboardStore.transient)
            _ = combined.withUnsafeBytes { sqlite3_bind_blob(stmt, 2, $0.baseAddress, Int32(combined.count), ClipboardStore.transient) }
            sqlite3_bind_double(stmt, 3, Date().timeIntervalSince1970)
            sqlite3_bind_int(stmt, 4, Int32(kind.rawValue))
            guard sqlite3_step(stmt) == SQLITE_DONE else { self.fail(.database); return }
            self.trim()
            self.invalidateSearch()
        }
    }

    /// Deduplication key: a keyed HMAC, so the database alone reveals nothing about the plaintext, not even by guessing.
    static func fingerprint(_ payload: Data, key: SymmetricKey) -> String {
        let dedupeKey = HKDF<SHA256>.deriveKey(inputKeyMaterial: key, info: Data("vey-clip-dedupe".utf8), outputByteCount: 32)
        return HMAC<SHA256>.authenticationCode(for: payload, using: dedupeKey).map { String(format: "%02x", $0) }.joined()
    }

    /// Searches decrypt the whole retained history once, then filter that copy on each keystroke
    /// instead of decrypting every entry again; any write discards the copy. Recent items with no
    /// search term read only the requested rows.
    func recent(limit: Int = 50, matching query: String = "") -> [ClipEntry] {
        guard state != .retrying else { return [] }
        guard !query.isEmpty else { return recentRows(limit: limit) }
        guard let entries = searchLock.withLock({ searchEntries }) ?? loadSearchEntries() else { return [] }
        let wantsImages = "image".contains(query.lowercased())
        let matches = Array(entries.lazy.filter { entry in
            entry.kind == .image ? wantsImages : entry.text.localizedCaseInsensitiveContains(query)
        }.prefix(limit))
        let imageIDs = matches.filter { $0.kind == .image }.map(\.id)
        let images = imageIDs.isEmpty ? [:] : imageData(for: Array(imageIDs))
        return matches.compactMap { entry in
            guard entry.kind == .image else { return ClipEntry(id: entry.id, kind: .text, text: entry.text, copiedAt: entry.copiedAt, imageData: nil) }
            guard let data = images[entry.id] else { return nil }
            return ClipEntry(id: entry.id, kind: .image, text: Self.imageTitle(entry.byteCount), copiedAt: entry.copiedAt, imageData: data)
        }
    }

    /// Releases the decrypted search copy when the launcher leaves clipboard search or hides.
    func endSearchSession() { invalidateSearch() }

    private func invalidateSearch() { searchLock.withLock { searchEntries = nil } }

    private static func imageTitle(_ byteCount: Int) -> String {
        "Image (\(ByteCountFormatter.string(fromByteCount: Int64(byteCount), countStyle: .file)))"
    }

    /// Bytes AES-GCM's combined form adds to a payload: a 12-byte nonce and a 16-byte tag.
    private static let sealOverhead = 28

    /// Decrypts every retained text entry for search. Images are listed by size without being
    /// read or decrypted: search matches them only by the word "image", and their bytes are
    /// decrypted later, only for the rows shown.
    private func loadSearchEntries() -> [SearchEntry]? {
        queue.sync {
            guard let key, let db else { return nil }
            var out: [SearchEntry] = []
            var stmt: OpaquePointer?
            let sql = "SELECT id, CASE WHEN kind = \(ClipEntry.Kind.image.rawValue) THEN NULL ELSE blob END, copied_at, kind, length(blob) FROM clips ORDER BY copied_at DESC LIMIT ?"
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { fail(.database); return nil }
            defer { sqlite3_finalize(stmt) }
            sqlite3_bind_int(stmt, 1, Int32(retention))
            var step = sqlite3_step(stmt)
            var complete = true
            while step == SQLITE_ROW {
                defer { step = sqlite3_step(stmt) }
                let id = sqlite3_column_int64(stmt, 0)
                let when = Date(timeIntervalSince1970: sqlite3_column_double(stmt, 2))
                if sqlite3_column_int(stmt, 3) == Int32(ClipEntry.Kind.image.rawValue) {
                    let size = max(0, Int(sqlite3_column_int64(stmt, 4)) - Self.sealOverhead)
                    out.append(SearchEntry(id: id, kind: .image, text: "", copiedAt: when, byteCount: size))
                    continue
                }
                guard let ptr = sqlite3_column_blob(stmt, 1) else { fail(.unreadableEntries); complete = false; continue }
                let data = Data(bytes: ptr, count: Int(sqlite3_column_bytes(stmt, 1)))
                guard let box = try? AES.GCM.SealedBox(combined: data),
                      let plain = try? AES.GCM.open(box, using: key) else { fail(.unreadableEntries); complete = false; continue }
                if let text = String(data: plain, encoding: .utf8) {
                    out.append(SearchEntry(id: id, kind: .text, text: text, copiedAt: when, byteCount: plain.count))
                }
            }
            if step != SQLITE_DONE { fail(.database); return out }
            if complete { searchLock.withLock { searchEntries = out } }
            return out
        }
    }

    private func imageData(for ids: [Int64]) -> [Int64: Data] {
        queue.sync {
            guard let key, let db else { return [:] }
            var out: [Int64: Data] = [:]
            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, "SELECT blob FROM clips WHERE id = ?", -1, &stmt, nil) == SQLITE_OK else { fail(.database); return [:] }
            defer { sqlite3_finalize(stmt) }
            for id in ids {
                sqlite3_reset(stmt)
                sqlite3_bind_int64(stmt, 1, id)
                guard sqlite3_step(stmt) == SQLITE_ROW, let ptr = sqlite3_column_blob(stmt, 0) else { continue }
                let data = Data(bytes: ptr, count: Int(sqlite3_column_bytes(stmt, 0)))
                guard let box = try? AES.GCM.SealedBox(combined: data), let plain = try? AES.GCM.open(box, using: key) else { fail(.unreadableEntries); continue }
                out[id] = plain
            }
            return out
        }
    }

    private func recentRows(limit: Int) -> [ClipEntry] {
        queue.sync {
            guard let key, let db else { return [] }
            var out: [ClipEntry] = []
            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, "SELECT id, blob, copied_at, kind FROM clips ORDER BY copied_at DESC LIMIT ?", -1, &stmt, nil) == SQLITE_OK else { fail(.database); return [] }
            defer { sqlite3_finalize(stmt) }
            sqlite3_bind_int(stmt, 1, Int32(limit))
            var step = sqlite3_step(stmt)
            while step == SQLITE_ROW {
                defer { step = sqlite3_step(stmt) }
                let id = sqlite3_column_int64(stmt, 0)
                guard let ptr = sqlite3_column_blob(stmt, 1) else { fail(.unreadableEntries); continue }
                let data = Data(bytes: ptr, count: Int(sqlite3_column_bytes(stmt, 1)))
                guard let box = try? AES.GCM.SealedBox(combined: data),
                      let plain = try? AES.GCM.open(box, using: key) else { fail(.unreadableEntries); continue }
                let kind = ClipEntry.Kind(rawValue: Int(sqlite3_column_int(stmt, 3))) ?? .text
                let when = Date(timeIntervalSince1970: sqlite3_column_double(stmt, 2))
                if kind == .image {
                    out.append(ClipEntry(id: id, kind: .image, text: Self.imageTitle(plain.count), copiedAt: when, imageData: plain))
                } else if let text = String(data: plain, encoding: .utf8) {
                    out.append(ClipEntry(id: id, kind: .text, text: text, copiedAt: when, imageData: nil))
                }
                if out.count >= limit { break }
            }
            if step != SQLITE_DONE && step != SQLITE_ROW { fail(.database) }
            return out
        }
    }

    func delete(id: Int64) {
        queue.async {
            guard self.failure == nil, let db = self.db else { return }
            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, "DELETE FROM clips WHERE id = ?", -1, &stmt, nil) == SQLITE_OK else { self.fail(.database); return }
            sqlite3_bind_int64(stmt, 1, id)
            if sqlite3_step(stmt) != SQLITE_DONE { self.fail(.database) }
            sqlite3_finalize(stmt)
            self.invalidateSearch()
        }
    }

    func clear() {
        queue.async {
            guard self.failure == nil else { return }
            if !self.execute("DELETE FROM clips") || !self.execute("VACUUM") { self.fail(.database) }
            self.invalidateSearch()
        }
    }

    private func trim() {
        invalidateSearch()
        guard failure == nil else { return }
        if !execute("DELETE FROM clips WHERE id NOT IN (SELECT id FROM clips ORDER BY copied_at DESC LIMIT \(max(10, retention)))") { fail(.database) }
    }

    private func execute(_ sql: String) -> Bool {
        guard let db else { return false }
        return sqlite3_exec(db, sql, nil, nil, nil) == SQLITE_OK
    }

    private func excludeFromBackup(_ url: URL) {
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        var u = url
        try? u.setResourceValues(values)
    }

    private static let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
}
