import Foundation

/// Ready-made groups of distracting websites and apps the owner can add to a block list.
public enum FocusCategory: String, Codable, CaseIterable, Identifiable, Sendable {
    case social, news, video, shopping, messaging, mail

    public var id: String { rawValue }

    public var title: LocalizedStringResource {
        switch self {
        case .social: return LocalizedStringResource("Social Media", table: "Core", comment: "Focus block category")
        case .news: return LocalizedStringResource("News", table: "Core", comment: "Focus block category")
        case .video: return LocalizedStringResource("Video and Streaming", table: "Core", comment: "Focus block category")
        case .shopping: return LocalizedStringResource("Shopping", table: "Core", comment: "Focus block category")
        case .messaging: return LocalizedStringResource("Messaging", table: "Core", comment: "Focus block category")
        case .mail: return LocalizedStringResource("Mail", table: "Core", comment: "Focus block category")
        }
    }

    /// Website rules in the category. Amazon is listed by its shop host so AWS stays reachable.
    public var websites: [String] {
        switch self {
        case .social: return ["x.com", "twitter.com", "facebook.com", "instagram.com", "threads.com", "threads.net", "bsky.app", "reddit.com", "tiktok.com", "linkedin.com", "pinterest.com", "tumblr.com", "mastodon.social"]
        case .news: return ["news.ycombinator.com", "nytimes.com", "cnn.com", "bbc.com", "bbc.co.uk", "theguardian.com", "washingtonpost.com", "foxnews.com", "theverge.com", "techmeme.com"]
        case .video: return ["youtube.com", "netflix.com", "twitch.tv", "hulu.com", "disneyplus.com", "max.com", "primevideo.com", "tv.apple.com"]
        case .shopping: return ["www.amazon.com", "ebay.com", "etsy.com", "walmart.com", "target.com", "bestbuy.com", "aliexpress.com", "temu.com"]
        case .messaging: return ["web.whatsapp.com", "discord.com", "app.slack.com", "messenger.com", "web.telegram.org"]
        case .mail: return ["mail.google.com", "outlook.live.com", "outlook.office.com", "mail.proton.me", "app.fastmail.com", "mail.yahoo.com"]
        }
    }

    /// Bundle identifiers of the category's Mac apps.
    public var apps: [String] {
        switch self {
        case .social, .shopping: return []
        case .news: return ["com.apple.news"]
        case .video: return ["com.apple.TV"]
        case .messaging: return ["com.tinyspeck.slackmacgap", "com.apple.MobileSMS", "com.hnc.Discord", "net.whatsapp.WhatsApp", "ru.keepcoder.Telegram", "org.telegram.desktop", "com.microsoft.teams2", "org.whispersystems.signal-desktop"]
        case .mail: return ["com.apple.mail", "com.microsoft.Outlook", "com.readdle.SparkDesktop", "com.mimestream.Mimestream", "com.superhuman.electron"]
        }
    }
}

/// What a Focus session is for and what it blocks. New sessions start from the last one's setup.
public struct FocusSetup: Codable, Equatable, Sendable {
    public static let maximumMinutes = 720
    public static let maximumGoalLength = 200
    public static let durationChoices = [15, 25, 30, 45, 60, 90]

    public var goal: String
    /// Session length in minutes; nil runs until the owner ends it.
    public var minutes: Int?
    public var apps: [String]
    public var websites: [String]
    public var categories: [FocusCategory]

    public init(goal: String = "", minutes: Int? = 25, apps: [String] = [], websites: [String] = [], categories: [FocusCategory] = [.social]) {
        self.goal = goal
        self.minutes = minutes
        self.apps = apps
        self.websites = websites
        self.categories = categories
        normalize()
    }

    /// Unknown categories, invalid websites and out-of-range lengths are dropped rather than
    /// failing, so a hand-edited or newer config still starts a session.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        goal = try c.decodeIfPresent(String.self, forKey: .goal) ?? ""
        minutes = try c.decodeIfPresent(Int.self, forKey: .minutes)
        apps = try c.decodeIfPresent([String].self, forKey: .apps) ?? []
        websites = try c.decodeIfPresent([String].self, forKey: .websites) ?? []
        categories = (try c.decodeIfPresent([String].self, forKey: .categories) ?? []).compactMap(FocusCategory.init(rawValue:))
        normalize()
    }

    /// Every app bundle identifier the setup blocks, its own and its categories', without duplicates.
    public var blockedApps: [String] {
        unique(apps + categories.flatMap(\.apps))
    }

    /// Every website rule the setup blocks, its own and its categories', without duplicates.
    public var blockedWebsites: [String] {
        unique(websites + categories.flatMap(\.websites))
    }

    public var blocksAnything: Bool { !blockedApps.isEmpty || !blockedWebsites.isEmpty }

    /// Trims the goal, clamps the length, turns typed websites into rules and removes duplicates.
    mutating func normalize() {
        goal = String(goal.trimmingCharacters(in: .whitespacesAndNewlines).prefix(Self.maximumGoalLength))
        minutes = minutes.map { min(max($0, 1), Self.maximumMinutes) }
        apps = unique(apps.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty })
        websites = unique(websites.compactMap(FocusHost.rule(from:)))
        categories = unique(categories)
    }

    private func unique<T: Hashable>(_ items: [T]) -> [T] {
        var seen = Set<T>()
        return items.filter { seen.insert($0).inserted }
    }
}

/// The owner's Focus settings in config.json: the setup new sessions start from and the snooze length.
public struct FocusPreferences: Codable, Equatable, Sendable {
    public static let snoozeRange = 1...30

    public var lastSetup = FocusSetup()
    public var snoozeMinutes = 3

    public init(lastSetup: FocusSetup = FocusSetup(), snoozeMinutes: Int = 3) {
        self.lastSetup = lastSetup
        self.snoozeMinutes = min(max(snoozeMinutes, Self.snoozeRange.lowerBound), Self.snoozeRange.upperBound)
    }

    /// Missing or out-of-range values fall back to defaults.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let snooze = try c.decodeIfPresent(Int.self, forKey: .snoozeMinutes) ?? 3
        self.init(lastSetup: try c.decodeIfPresent(FocusSetup.self, forKey: .lastSetup) ?? FocusSetup(), snoozeMinutes: snooze)
    }
}
