import Foundation
import SQLite3

struct UsageRecord {
    let key: String
    let score: Double
    let last: Date
}

/// Records what the user chose, and for which exact query. Plain SQLite in the container; the keys are
/// row identities such as an app path or a quicklink name, nothing sensitive.
final class UsageStore {
    private var db: OpaquePointer?
    private let queue = DispatchQueue(label: "com.mysticcoders.vey.usage")
    private var cache: [String: UsageRecord] = [:]
    private var queryCache: [String: String] = [:]

    init(url: URL? = nil) {
        let path = (url ?? Preferences.supportDirectory.appendingPathComponent("usage.sqlite")).path
        if sqlite3_open(path, &db) == SQLITE_OK {
            exec("CREATE TABLE IF NOT EXISTS usage (key TEXT PRIMARY KEY, score REAL NOT NULL, last REAL NOT NULL)")
            exec("CREATE TABLE IF NOT EXISTS query_choice (query TEXT PRIMARY KEY, key TEXT NOT NULL, last REAL NOT NULL)")
            load()
        }
    }

    deinit { sqlite3_close(db) }

    /// Effective score right now, zero if never used.
    func score(_ key: String) -> Double {
        guard let r = cache[key] else { return 0 }
        return Frecency.decayed(score: r.score, last: r.last)
    }

    /// The key last chosen for exactly this query, if any.
    func choice(forQuery query: String) -> String? {
        queryCache[UsageStore.normalize(query)]
    }

    func record(key: String, query: String) {
        let now = Date()
        let prev = cache[key]
        let score = prev.map { Frecency.bumped(score: $0.score, last: $0.last, now: now) } ?? 1
        cache[key] = UsageRecord(key: key, score: score, last: now)
        let q = UsageStore.normalize(query)
        if !q.isEmpty { queryCache[q] = key }
        queue.async { [weak self] in
            guard let self, let db = self.db else { return }
            var stmt: OpaquePointer?
            if sqlite3_prepare_v2(db, "INSERT INTO usage (key, score, last) VALUES (?, ?, ?) ON CONFLICT(key) DO UPDATE SET score = excluded.score, last = excluded.last", -1, &stmt, nil) == SQLITE_OK {
                sqlite3_bind_text(stmt, 1, key, -1, UsageStore.transient)
                sqlite3_bind_double(stmt, 2, score)
                sqlite3_bind_double(stmt, 3, now.timeIntervalSince1970)
                sqlite3_step(stmt)
            }
            sqlite3_finalize(stmt)
            if !q.isEmpty, sqlite3_prepare_v2(db, "INSERT INTO query_choice (query, key, last) VALUES (?, ?, ?) ON CONFLICT(query) DO UPDATE SET key = excluded.key, last = excluded.last", -1, &stmt, nil) == SQLITE_OK {
                sqlite3_bind_text(stmt, 1, q, -1, UsageStore.transient)
                sqlite3_bind_text(stmt, 2, key, -1, UsageStore.transient)
                sqlite3_bind_double(stmt, 3, now.timeIntervalSince1970)
                sqlite3_step(stmt)
                sqlite3_finalize(stmt)
            }
        }
    }

    /// Keys ordered by effective score, highest first.
    func top(prefix: String, limit: Int) -> [String] {
        cache.values
            .filter { $0.key.hasPrefix(prefix) }
            .map { ($0.key, Frecency.decayed(score: $0.score, last: $0.last)) }
            .filter { $0.1 > 0.05 }
            .sorted { $0.1 > $1.1 }
            .prefix(limit)
            .map(\.0)
    }

    static func normalize(_ q: String) -> String { q.trimmingCharacters(in: .whitespaces).lowercased() }

    private func load() {
        guard let db else { return }
        var stmt: OpaquePointer?
        if sqlite3_prepare_v2(db, "SELECT key, score, last FROM usage", -1, &stmt, nil) == SQLITE_OK {
            while sqlite3_step(stmt) == SQLITE_ROW {
                let key = String(cString: sqlite3_column_text(stmt, 0))
                cache[key] = UsageRecord(key: key, score: sqlite3_column_double(stmt, 1), last: Date(timeIntervalSince1970: sqlite3_column_double(stmt, 2)))
            }
        }
        sqlite3_finalize(stmt)
        if sqlite3_prepare_v2(db, "SELECT query, key FROM query_choice", -1, &stmt, nil) == SQLITE_OK {
            while sqlite3_step(stmt) == SQLITE_ROW {
                queryCache[String(cString: sqlite3_column_text(stmt, 0))] = String(cString: sqlite3_column_text(stmt, 1))
            }
        }
        sqlite3_finalize(stmt)
    }

    private func exec(_ sql: String) { if let db { sqlite3_exec(db, sql, nil, nil, nil) } }
    private static let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
}
