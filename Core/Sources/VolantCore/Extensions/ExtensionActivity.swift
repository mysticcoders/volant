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

    public mutating func clear() { events = []; dropped = 0 }
}
