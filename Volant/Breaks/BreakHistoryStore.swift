import Foundation
import VolantCore

/// Keeps the owner's break records in `break-history.json` beside the schedule, on this Mac only.
/// Records hold the kind, start and length of each break and are pruned to `BreakHistory.keptDays`.
/// Reading tolerates a missing or damaged file; a failed write loses only that record.
enum BreakHistoryStore {
    static var defaultURL: URL { Preferences.supportDirectory.appendingPathComponent("break-history.json") }

    /// The saved records, or none when the file is missing or can't be read.
    static func load(url: URL = defaultURL) -> [BreakRecord] {
        guard let data = try? Data(contentsOf: url) else { return [] }
        return (try? JSONDecoder().decode([BreakRecord].self, from: data)) ?? []
    }

    /// Adds a record and drops old ones; returns whether the file was written.
    @discardableResult
    static func append(_ record: BreakRecord, url: URL = defaultURL, now: Date) -> Bool {
        guard BreakHistory.keeps(record) else { return true }
        let records = BreakHistory.pruned(load(url: url) + [record], now: now)
        guard let data = try? JSONEncoder().encode(records) else { return false }
        return (try? data.write(to: url, options: .atomic)) != nil
    }

    /// Forgets every record; returns whether nothing is left on disk.
    @discardableResult
    static func clear(url: URL = defaultURL) -> Bool {
        do {
            try FileManager.default.removeItem(at: url)
            return true
        } catch CocoaError.fileNoSuchFile {
            return true
        } catch {
            return !FileManager.default.fileExists(atPath: url.path)
        }
    }
}
