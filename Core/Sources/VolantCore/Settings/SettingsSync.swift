import Foundation

/// Merges the settings that follow the owner between Macs with a key-value cloud store. config.json
/// stays the source of truth on each Mac: only the listed top-level keys are exchanged, each one as
/// its raw JSON value so unknown fields inside a synced block survive. Every other key, including
/// unknown ones, is never read from or written to the cloud.
public enum SettingsSync {
    /// Settings that mean the same thing on every Mac. App shortcuts and favorites name installed
    /// bundles, and Dock, status bar, AI and extension choices belong to one machine.
    public static let keys = ["summonHotKey", "notesHotKey", "emojiHotKey", "talkHotKey", "clipboardRetention",
                              "snippets", "quicklinks", "aliases", "appearance"]

    /// iCloud key-value storage allows 1 MB per app; the margin covers key names and envelopes.
    public static let byteBudget = 960_000

    /// One synced value as stored in the cloud: canonical JSON and when a Mac last sent it.
    public struct Entry: Equatable {
        public var value: Data
        public var modified: Date

        public init(value: Data, modified: Date) {
            self.value = value
            self.modified = modified
        }

        /// Reads a stored envelope, re-encoding its JSON so byte comparison is stable. Anything
        /// malformed reads as absent rather than being applied.
        public init?(propertyList: Any?) {
            guard let dictionary = propertyList as? [String: Any],
                  let data = dictionary["value"] as? Data,
                  let modified = dictionary["modified"] as? Double,
                  let object = try? JSONSerialization.jsonObject(with: data, options: .fragmentsAllowed),
                  let value = try? SettingsSync.canonical(object) else { return nil }
            self.value = value
            self.modified = Date(timeIntervalSince1970: modified)
        }

        public var propertyList: [String: Any] { ["value": value, "modified": modified.timeIntervalSince1970] }
    }

    /// The last value this Mac and the cloud agreed on for each key. Kept outside config.json so a
    /// backup or import never carries one Mac's sync history to another.
    public struct State: Codable, Equatable {
        public var baseline: [String: Data]

        public init(baseline: [String: Data] = [:]) {
            self.baseline = baseline
        }
    }

    public struct Outcome {
        /// The new config.json, or nil when nothing arrived from the cloud.
        public var config: Data?
        public var uploads: [String: Entry]
        public var state: State
        public var received: [String]
        public var sent: [String]
        /// Cloud values that would make config.json invalid; they are left unapplied.
        public var rejected: [String]
        /// Local changes held back because the synced settings exceed the cloud store's limit.
        public var overBudget: Bool
    }

    public enum Failure: Error, LocalizedError, Equatable {
        case unreadableConfig

        public var errorDescription: String? {
            switch self {
            case .unreadableConfig: return "config.json could not be read, so settings were not synced."
            }
        }
    }

    public static var stateURL: URL { Preferences.supportDirectory.appendingPathComponent("icloud-sync.json") }

    /// Three-way merge per key against the last agreed value. A side that alone moved away from the
    /// baseline wins; when both moved, the later of the config file's modification date and the
    /// cloud entry wins. Without a baseline, as on first enable or after an account change, a value
    /// already in the cloud is adopted so a new Mac picks up existing settings. A malformed config
    /// throws and nothing is exchanged.
    public static func reconcile(config: Data, modified: Date, remote: [String: Entry], state: State, now: Date = Date()) throws -> Outcome {
        guard var object = (try? JSONSerialization.jsonObject(with: config)) as? [String: Any],
              (try? JSONDecoder().decode(Preferences.self, from: config)) != nil else { throw Failure.unreadableConfig }
        let defaults = try JSONSerialization.jsonObject(with: JSONEncoder().encode(Preferences())) as? [String: Any] ?? [:]
        var baseline = state.baseline
        var pending: [String: Entry] = [:]
        var received: [String] = [], rejected: [String] = []
        var final: [String: Data] = [:]

        for key in keys {
            guard let local = try? canonical(object[key] ?? defaults[key] ?? NSNull()) else { continue }
            final[key] = local
            let base = baseline[key]
            guard let cloud = remote[key] else {
                pending[key] = Entry(value: local, modified: now)
                continue
            }
            if cloud.value == local { baseline[key] = local; continue }
            let adoptCloud: Bool
            if base == nil || base == local { adoptCloud = true }
            else if base == cloud.value { adoptCloud = false }
            else { adoptCloud = cloud.modified >= modified }
            guard adoptCloud else {
                pending[key] = Entry(value: local, modified: now)
                continue
            }
            var candidate = object
            candidate[key] = try JSONSerialization.jsonObject(with: cloud.value, options: .fragmentsAllowed)
            if let data = try? JSONSerialization.data(withJSONObject: candidate),
               (try? JSONDecoder().decode(Preferences.self, from: data)) != nil {
                object = candidate
                baseline[key] = cloud.value
                final[key] = cloud.value
                received.append(key)
            } else {
                rejected.append(key)
            }
        }

        let size = final.reduce(0) { $0 + $1.key.utf8.count + $1.value.count }
        let overBudget = !pending.isEmpty && size > byteBudget
        if !overBudget {
            for (key, entry) in pending { baseline[key] = entry.value }
        }
        let updated = received.isEmpty ? nil : try JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys])
        return Outcome(config: updated, uploads: overBudget ? [:] : pending, state: State(baseline: baseline),
                       received: received, sent: overBudget ? [] : keys.filter { pending[$0] != nil },
                       rejected: rejected, overBudget: overBudget)
    }

    /// Sorted, slash-preserving JSON so the same setting encodes to the same bytes on every Mac.
    public static func canonical(_ value: Any) throws -> Data {
        try JSONSerialization.data(withJSONObject: value, options: [.sortedKeys, .fragmentsAllowed, .withoutEscapingSlashes])
    }

    public static func loadState(at url: URL = stateURL) -> State? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(State.self, from: data)
    }

    public static func saveState(_ state: State, at url: URL = stateURL) throws {
        try JSONEncoder().encode(state).write(to: url, options: .atomic)
    }

    /// Keeps a copy of this Mac's config.json before sync first runs, since adopting the cloud's
    /// settings replaces local values. An existing copy is never replaced; a numbered name is used
    /// instead. Returns the copy's location.
    @discardableResult
    public static func preserve(configAt url: URL, on date: Date = Date()) throws -> URL {
        let data = try Data(contentsOf: url)
        let stamp = date.formatted(.iso8601.year().month().day().time(includingFractionalSeconds: false).timeSeparator(.omitted))
        let directory = url.deletingLastPathComponent()
        for attempt in 1...100 {
            let suffix = attempt == 1 ? "" : "-\(attempt)"
            let copy = directory.appendingPathComponent("config.before-icloud-\(stamp)\(suffix).json")
            do {
                try data.write(to: copy, options: .withoutOverwriting)
                return copy
            } catch CocoaError.fileWriteFileExists {
                continue
            }
        }
        throw CocoaError(.fileWriteFileExists)
    }
}
