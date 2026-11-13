import Foundation

/// How Breaks measure a stretch of work.
public enum BreakMode: String, Codable, CaseIterable, Identifiable, Sendable {
    /// Only minutes the owner is at the Mac count. Being away for the break length counts as a break.
    case activeTime = "active"
    /// Wall-clock minutes since the last break, whatever the owner is doing.
    case clockTime = "clock"

    public var id: String { rawValue }

    public var title: LocalizedStringResource {
        switch self {
        case .activeTime: return LocalizedStringResource("Active Time", table: "Core", comment: "Breaks timing mode: count only minutes the owner is at the Mac")
        case .clockTime: return LocalizedStringResource("Clock Time", table: "Core", comment: "Breaks timing mode: count wall-clock minutes since the last break")
        }
    }
}

/// How firmly a due break asks the owner to step away.
public enum BreakStrictness: String, Codable, CaseIterable, Identifiable, Sendable {
    /// A reminder panel with Start Break, Postpone and Skip; the screen is never covered.
    case gentle
    /// A dimmed overlay on every display with a countdown, Postpone and Skip.
    case standard
    /// The overlay without Postpone; Skip appears after a short delay and must be held.
    case strict

    public var id: String { rawValue }

    public var title: LocalizedStringResource {
        switch self {
        case .gentle: return LocalizedStringResource("Gentle", table: "Core", comment: "Breaks strictness: a reminder panel, never full screen")
        case .standard: return LocalizedStringResource("Standard", table: "Core", comment: "Breaks strictness: a full-screen overlay with Postpone and Skip")
        case .strict: return LocalizedStringResource("Strict", table: "Core", comment: "Breaks strictness: a full-screen overlay whose Skip must be held")
        }
    }

    /// Whether a running break covers the screen instead of showing the reminder panel.
    public var coversScreen: Bool { self != .gentle }
}

/// The owner's Break settings in config.json under `breaks`. Off by default; per-Mac, never synced.
public struct BreakPreferences: Codable, Equatable, Sendable {
    public static let intervalRange = 10...180
    public static let lengthRange = 1...30
    public static let postponeMinutes = 5
    /// How long before a break the heads-up notice appears.
    public static let headsUpSeconds: TimeInterval = 60

    public var enabled: Bool
    public var mode: BreakMode
    /// Minutes of work between breaks.
    public var intervalMinutes: Int
    /// Minutes a break lasts.
    public var breakMinutes: Int
    public var strictness: BreakStrictness
    /// Whether a notice appears a minute before each break.
    public var headsUp: Bool

    public init(enabled: Bool = false, mode: BreakMode = .activeTime, intervalMinutes: Int = 45, breakMinutes: Int = 5,
                strictness: BreakStrictness = .standard, headsUp: Bool = true) {
        self.enabled = enabled
        self.mode = mode
        self.intervalMinutes = min(max(intervalMinutes, Self.intervalRange.lowerBound), Self.intervalRange.upperBound)
        self.breakMinutes = min(max(breakMinutes, Self.lengthRange.lowerBound), Self.lengthRange.upperBound)
        self.strictness = strictness
        self.headsUp = headsUp
    }

    /// Missing, unknown or out-of-range values fall back to defaults or are clamped, so a
    /// hand-edited or newer config still loads.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = BreakPreferences()
        self.init(enabled: (try? c.decodeIfPresent(Bool.self, forKey: .enabled)) ?? d.enabled,
                  mode: (try? c.decodeIfPresent(String.self, forKey: .mode)).flatMap(BreakMode.init(rawValue:)) ?? d.mode,
                  intervalMinutes: (try? c.decodeIfPresent(Int.self, forKey: .intervalMinutes)) ?? d.intervalMinutes,
                  breakMinutes: (try? c.decodeIfPresent(Int.self, forKey: .breakMinutes)) ?? d.breakMinutes,
                  strictness: (try? c.decodeIfPresent(String.self, forKey: .strictness)).flatMap(BreakStrictness.init(rawValue:)) ?? d.strictness,
                  headsUp: (try? c.decodeIfPresent(Bool.self, forKey: .headsUp)) ?? d.headsUp)
    }

    var interval: TimeInterval { TimeInterval(intervalMinutes) * 60 }
    var length: TimeInterval { TimeInterval(breakMinutes) * 60 }
}
