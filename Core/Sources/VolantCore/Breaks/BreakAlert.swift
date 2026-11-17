import Foundation

/// What Volant for iPhone hears about a break: that one started on the Mac, or that one ran to its
/// end. The Mac writes one CloudKit record per kind, always under the same name, to the owner's
/// private database in the shared container; the iPhone's subscriptions turn each write into a
/// notification, which a paired Apple Watch shows too. A record holds only the moment, never the
/// owner's settings, history or what they were doing.
public enum BreakAlert: Equatable, Sendable {
    case started
    case over

    public static let containerIdentifier = "iCloud.com.mysticcoders.volant"
    /// Every alert overwrites the record of its kind, so the database never holds more than two.
    public static let recordName = "latest"
    /// The record's only field: when the break started or ended.
    public static let timeField = "at"

    /// The CloudKit record type, and the iPhone subscription that listens for it.
    public var recordType: String {
        switch self {
        case .started: return "BreakStarted"
        case .over: return "BreakOver"
        }
    }

    public var subscriptionID: String {
        switch self {
        case .started: return "break-started"
        case .over: return "break-over"
        }
    }

    /// The notification text on the iPhone and Apple Watch. Volant for iPhone is English only.
    public var notificationTitle: String {
        switch self {
        case .started: return "Time for a break"
        case .over: return "Break’s over"
        }
    }

    public var notificationBody: String {
        switch self {
        case .started: return "Step away from your Mac for a few minutes."
        case .over: return "Welcome back. Your Mac is ready when you are."
        }
    }

    /// The alert a schedule change calls for: `started` when a break began, `over` when a break
    /// ran its full length. A break ended early, skipped or counted at relaunch sends nothing, since
    /// the owner is at the Mac or the moment has passed.
    public static func between(_ before: BreakSchedule, _ after: BreakSchedule, finished: BreakRecord?) -> BreakAlert? {
        if after.isOnBreak, !before.isOnBreak || before.breakStartedAt != after.breakStartedAt {
            return .started
        }
        if let finished, finished.kind == .taken, finished.planned > 0, finished.seconds >= finished.planned, before.isOnBreak {
            return .over
        }
        return nil
    }
}
