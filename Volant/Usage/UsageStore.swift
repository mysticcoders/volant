import Foundation
import SQLite3
import VolantCore

struct UsageRecord {
    let key: String
    let score: Double
    let last: Date
}

/// Records what the user chose, and for which exact query. Plain SQLite in the container; the keys are
/// row identities such as an app path or a quicklink name, nothing sensitive. `daily_use` keeps only a
/// count per local day for Settings › Your Volant: no keys, no queries, nothing sent anywhere.
final class UsageStore {
    /// Days of activity kept; older days are dropped when the store opens.
    static let activityRetentionDays = 400
    static var defaultURL: URL { Preferences.supportDirectory.appendingPathComponent("usage.sqlite") }
    private var db: OpaquePointer?
    private let queue = DispatchQueue(label: "com.mysticcoders.volant.usage")
    private var cache: [String: UsageRecord] = [:]
    private var queryCache: [String: String] = [:]

    init(url: URL? = nil) {
        let path = (url ?? Self.defaultURL).path
        if sqlite3_open(path, &db) == SQLITE_OK {
            sqlite3_busy_timeout(db, 500)
            exec("CREATE TABLE IF NOT EXISTS usage (key TEXT PRIMARY KEY, score REAL NOT NULL, last REAL NOT NULL)")
            exec("CREATE TABLE IF NOT EXISTS query_choice (query TEXT PRIMARY KEY, key TEXT NOT NULL, last REAL NOT NULL)")
            exec("CREATE TABLE IF NOT EXISTS daily_use (day TEXT PRIMARY KEY, uses INTEGER NOT NULL)")
            pruneActivity()
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
        let day = UsageStats.dayKey(now)
        queue.async { [weak self] in
            guard let self, let db = self.db else { return }
            var stmt: OpaquePointer?
            if sqlite3_prepare_v2(db, "INSERT INTO daily_use (day, uses) VALUES (?, 1) ON CONFLICT(day) DO UPDATE SET uses = uses + 1", -1, &stmt, nil) == SQLITE_OK {
                sqlite3_bind_text(stmt, 1, day, -1, UsageStore.transient)
                sqlite3_step(stmt)
            }
            sqlite3_finalize(stmt)
            stmt = nil
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

    /// Waits for pending writes, for a caller about to read the file through another connection.
    func drain() { queue.sync {} }

    /// Drain pending records before removing both ranking and exact-query learning.
    func resetRanking(for key: String) -> Bool {
        let saved = queue.sync { () -> Bool in
            guard let db, sqlite3_exec(db, "BEGIN IMMEDIATE", nil, nil, nil) == SQLITE_OK else { return false }
            var committed = false
            defer { if !committed { sqlite3_exec(db, "ROLLBACK", nil, nil, nil) } }
            for sql in ["DELETE FROM usage WHERE key = ?", "DELETE FROM query_choice WHERE key = ?"] {
                var statement: OpaquePointer?
                guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else { return false }
                defer { sqlite3_finalize(statement) }
                sqlite3_bind_text(statement, 1, key, -1, Self.transient)
                guard sqlite3_step(statement) == SQLITE_DONE else { return false }
            }
            committed = sqlite3_exec(db, "COMMIT", nil, nil, nil) == SQLITE_OK
            return committed
        }
        if saved {
            cache.removeValue(forKey: key)
            queryCache = queryCache.filter { $0.value != key }
        }
        return saved
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

    /// Drops activity days older than the retention window, measured from today.
    private func pruneActivity() {
        guard let db, let cutoff = Calendar.current.date(byAdding: .day, value: -Self.activityRetentionDays, to: Date()) else { return }
        var stmt: OpaquePointer?
        if sqlite3_prepare_v2(db, "DELETE FROM daily_use WHERE day < ?", -1, &stmt, nil) == SQLITE_OK {
            sqlite3_bind_text(stmt, 1, UsageStats.dayKey(cutoff), -1, Self.transient)
            sqlite3_step(stmt)
        }
        sqlite3_finalize(stmt)
    }

    /// Reads the per-day counts and ranking rows for Settings through a read-only connection, so the
    /// window never writes over the launcher's store. A missing file or table reads as empty.
    static func snapshot(url: URL = UsageStore.defaultURL) -> (daily: [String: Int], records: [UsageStats.Ranked]) {
        var db: OpaquePointer?
        defer { sqlite3_close(db) }
        guard sqlite3_open_v2(url.path, &db, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else { return ([:], []) }
        sqlite3_busy_timeout(db, 500)
        var daily: [String: Int] = [:]
        var records: [UsageStats.Ranked] = []
        var stmt: OpaquePointer?
        if sqlite3_prepare_v2(db, "SELECT day, uses FROM daily_use", -1, &stmt, nil) == SQLITE_OK {
            while sqlite3_step(stmt) == SQLITE_ROW {
                daily[String(cString: sqlite3_column_text(stmt, 0))] = Int(sqlite3_column_int64(stmt, 1))
            }
        }
        sqlite3_finalize(stmt)
        stmt = nil
        if sqlite3_prepare_v2(db, "SELECT key, score, last FROM usage", -1, &stmt, nil) == SQLITE_OK {
            while sqlite3_step(stmt) == SQLITE_ROW {
                records.append(UsageStats.Ranked(key: String(cString: sqlite3_column_text(stmt, 0)), score: sqlite3_column_double(stmt, 1),
                                                 last: Date(timeIntervalSince1970: sqlite3_column_double(stmt, 2))))
            }
        }
        sqlite3_finalize(stmt)
        return (daily, records)
    }

    /// Forgets every per-day count while keeping launcher ranking, which has its own reset per item.
    static func clearActivity(url: URL = UsageStore.defaultURL) -> Bool {
        var db: OpaquePointer?
        defer { sqlite3_close(db) }
        guard sqlite3_open_v2(url.path, &db, SQLITE_OPEN_READWRITE, nil) == SQLITE_OK else { return false }
        sqlite3_busy_timeout(db, 500)
        return sqlite3_exec(db, "CREATE TABLE IF NOT EXISTS daily_use (day TEXT PRIMARY KEY, uses INTEGER NOT NULL); DELETE FROM daily_use", nil, nil, nil) == SQLITE_OK
    }

    private func exec(_ sql: String) { if let db { sqlite3_exec(db, sql, nil, nil, nil) } }
    private static let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
}
