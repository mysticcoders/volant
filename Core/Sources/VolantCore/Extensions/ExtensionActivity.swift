import Foundation

/// One thing an extension did or asked to do, recorded by Volant where it checks or performs the
/// operation, never from anything the extension reports about itself. It holds bounded metadata only:
/// never the query, clipboard text, rows, headers, tokens, URL paths or queries, log text or raw errors.
/// A fetch names its host, which is still private: activity stays on this Mac and is not persisted.
public struct ExtensionActivity: Equatable, Sendable {
    public enum Operation: String, Sendable {
        /// One call into the module; `detail` is its phase: plan, render, action, opened or run.
        case module
        /// A GET or a row action's POST; `detail` is the host.
        case fetch, post
        case clipboardRead, clipboardWrite, log, location, storageSave
        /// Drawing a row image's SVG preview in the extension helper: completed, denied (the markup was
        /// refused), timedOut or failed. Never carries any of the markup.
        case svgRender
    }

    public enum Outcome: String, Sendable {
        case completed, failed, denied, cancelled, timedOut
    }

    public let extensionID: String
    public let version: String
    public let codeHash: String
    /// Every event of one run shares this number, so its steps can be put back together in order.
    public let invocation: Int
    public let time: Date
    public let operation: Operation
    public let outcome: Outcome
    public let detail: String?
    public let duration: TimeInterval?

    public static let maximumDetailLength = 64

    public init(extensionID: String, version: String, codeHash: String, invocation: Int, time: Date, operation: Operation,
                outcome: Outcome, detail: String? = nil, duration: TimeInterval? = nil) {
        self.extensionID = String(extensionID.prefix(128)); self.version = String(version.prefix(64)); self.codeHash = String(codeHash.prefix(64))
        self.invocation = invocation; self.time = time; self.operation = operation; self.outcome = outcome
        self.detail = detail.map { String($0.prefix(Self.maximumDetailLength)) }; self.duration = duration
    }

    /// The host of a URL an extension asked for, if it is a valid hostname, and nothing else of it.
    public static func host(of url: String) -> String? {
        guard let host = URLComponents(string: url)?.host?.lowercased(), ExtensionNetwork.isValidHost(host) else { return nil }
        return host
    }
}

/// The newest activity in memory, at most `capacity` events. It counts the events it had to drop, so
/// a reader never mistakes a trimmed history for a complete one.
public struct ExtensionActivityLog: Equatable, Sendable {
    public static let defaultCapacity = 500
    public let capacity: Int
    public private(set) var events: [ExtensionActivity] = []
    public private(set) var dropped = 0

    public init(capacity: Int = defaultCapacity) { self.capacity = max(1, capacity) }

    public mutating func record(_ event: ExtensionActivity) {
        events.append(event)
        if events.count > capacity {
            let excess = events.count - capacity
            events.removeFirst(excess)
            dropped += excess
        }
    }

    public func events(for extensionID: String) -> [ExtensionActivity] { events.filter { $0.extensionID == extensionID } }

    /// What the Activity history shows: newest first, for one extension or all of them, and only the
    /// events that didn't complete when `problemsOnly` is set.
    public func visible(extensionID: String?, problemsOnly: Bool) -> [ExtensionActivity] {
        events.reversed().filter { event in
            (extensionID == nil || event.extensionID == extensionID) && (!problemsOnly || event.outcome != .completed)
        }
    }

    /// Every extension that has activity, in the order each first appears.
    public var extensionIDs: [String] {
        var seen = Set<String>()
        return events.map(\.extensionID).filter { seen.insert($0).inserted }
    }

    public mutating func clear() { events = []; dropped = 0 }
}

/// The Activity history as a file the owner saves: exactly the fields each event holds, as JSON, with the
/// count of older events the log dropped, so an export never reads as a complete record when it isn't.
public enum ExtensionActivityExport {
    private struct File: Encodable {
        let exportedAt: Date
        let note: String
        let droppedEarlierEvents: Int
        let events: [Event]
    }

    private struct Event: Encodable {
        let extensionID: String
        let version: String
        let codeHash: String
        let invocation: Int
        let time: Date
        let operation: String
        let outcome: String
        let detail: String?
        let durationMilliseconds: Int?
    }

    public static func json(_ events: [ExtensionActivity], dropped: Int, exportedAt: Date) throws -> Data {
        let file = File(exportedAt: exportedAt,
                        note: "What Volant observed extensions do since it started. Kept in memory only, never persisted.",
                        droppedEarlierEvents: dropped,
                        events: events.map { event in
                            Event(extensionID: event.extensionID, version: event.version, codeHash: event.codeHash,
                                  invocation: event.invocation, time: event.time, operation: event.operation.rawValue,
                                  outcome: event.outcome.rawValue, detail: event.detail,
                                  durationMilliseconds: event.duration.map { Int(($0 * 1000).rounded()) })
                        })
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(file)
    }
}
