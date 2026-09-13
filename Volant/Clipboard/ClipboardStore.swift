import Foundation
import SQLite3
import CryptoKit

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
    private var db: OpaquePointer?
    private let key: SymmetricKey?
    var retention: Int { didSet { queue.async { self.trim() } } }
    private let queue = DispatchQueue(label: "com.mysticcoders.volant.clipboard")

    init(retention: Int) {
        self.retention = max(10, retention)
        self.key = KeychainKey.load()
        let url = Preferences.supportDirectory.appendingPathComponent("clipboard.sqlite")
        if sqlite3_open(url.path, &db) == SQLITE_OK {
            exec("PRAGMA secure_delete = ON")
            exec("PRAGMA journal_mode = DELETE")
            exec("CREATE TABLE IF NOT EXISTS clips (id INTEGER PRIMARY KEY AUTOINCREMENT, hash TEXT UNIQUE, blob BLOB NOT NULL, copied_at REAL NOT NULL)")
            exec("CREATE INDEX IF NOT EXISTS clips_copied_at ON clips (copied_at DESC)")
            exec("ALTER TABLE clips ADD COLUMN kind INTEGER NOT NULL DEFAULT 0")
            excludeFromBackup(url)
        }
    }

    deinit { sqlite3_close(db) }

    func record(_ text: String) { store(Data(text.utf8), kind: .text) }

    /// Images are stored as PNG bytes, encrypted exactly like text.
    func recordImage(_ png: Data) { store(png, kind: .image) }

    private func store(_ payload: Data, kind: ClipEntry.Kind) {
        guard let key, let db else { return }
        queue.async {
            let hash = ClipboardStore.fingerprint(payload, key: key)
            guard let sealed = try? AES.GCM.seal(payload, using: key), let combined = sealed.combined else { return }
            var stmt: OpaquePointer?
            let sql = "INSERT INTO clips (hash, blob, copied_at, kind) VALUES (?, ?, ?, ?) ON CONFLICT(hash) DO UPDATE SET copied_at = excluded.copied_at"
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return }
            defer { sqlite3_finalize(stmt) }
            sqlite3_bind_text(stmt, 1, hash, -1, ClipboardStore.transient)
            combined.withUnsafeBytes { sqlite3_bind_blob(stmt, 2, $0.baseAddress, Int32(combined.count), ClipboardStore.transient) }
            sqlite3_bind_double(stmt, 3, Date().timeIntervalSince1970)
            sqlite3_bind_int(stmt, 4, Int32(kind.rawValue))
            sqlite3_step(stmt)
            self.trim()
        }
    }

    /// Deduplication key: a keyed HMAC, so the database alone reveals nothing about the plaintext, not even by guessing.
    static func fingerprint(_ payload: Data, key: SymmetricKey) -> String {
        let dedupeKey = HKDF<SHA256>.deriveKey(inputKeyMaterial: key, info: Data("vey-clip-dedupe".utf8), outputByteCount: 32)
        return HMAC<SHA256>.authenticationCode(for: payload, using: dedupeKey).map { String(format: "%02x", $0) }.joined()
    }

    func recent(limit: Int = 50, matching query: String = "") -> [ClipEntry] {
        guard let key, let db else { return [] }
        return queue.sync {
            var out: [ClipEntry] = []
            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, "SELECT id, blob, copied_at, kind FROM clips ORDER BY copied_at DESC LIMIT ?", -1, &stmt, nil) == SQLITE_OK else { return [] }
            defer { sqlite3_finalize(stmt) }
            sqlite3_bind_int(stmt, 1, Int32(query.isEmpty ? limit : retention))
            while sqlite3_step(stmt) == SQLITE_ROW {
                let id = sqlite3_column_int64(stmt, 0)
                guard let ptr = sqlite3_column_blob(stmt, 1) else { continue }
                let data = Data(bytes: ptr, count: Int(sqlite3_column_bytes(stmt, 1)))
                guard let box = try? AES.GCM.SealedBox(combined: data),
                      let plain = try? AES.GCM.open(box, using: key) else { continue }
                let kind = ClipEntry.Kind(rawValue: Int(sqlite3_column_int(stmt, 3))) ?? .text
                let when = Date(timeIntervalSince1970: sqlite3_column_double(stmt, 2))
                if kind == .image {
                    if query.isEmpty || "image".contains(query.lowercased()) {
                        out.append(ClipEntry(id: id, kind: .image, text: "Image (\(ByteCountFormatter.string(fromByteCount: Int64(plain.count), countStyle: .file)))", copiedAt: when, imageData: plain))
                    }
                } else if let text = String(data: plain, encoding: .utf8), query.isEmpty || text.localizedCaseInsensitiveContains(query) {
                    out.append(ClipEntry(id: id, kind: .text, text: text, copiedAt: when, imageData: nil))
                }
                if out.count >= limit { break }
            }
            return out
        }
    }

    func delete(id: Int64) {
        guard let db else { return }
        queue.async {
            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, "DELETE FROM clips WHERE id = ?", -1, &stmt, nil) == SQLITE_OK else { return }
            sqlite3_bind_int64(stmt, 1, id)
            sqlite3_step(stmt)
            sqlite3_finalize(stmt)
        }
    }

    func clear() {
        queue.async {
            self.exec("DELETE FROM clips")
            self.exec("VACUUM")
        }
    }

    private func trim() {
        exec("DELETE FROM clips WHERE id NOT IN (SELECT id FROM clips ORDER BY copied_at DESC LIMIT \(retention))")
    }

    private func exec(_ sql: String) {
        guard let db else { return }
        sqlite3_exec(db, sql, nil, nil, nil)
    }

    private func excludeFromBackup(_ url: URL) {
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        var u = url
        try? u.setResourceValues(values)
    }

    private static let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
}
