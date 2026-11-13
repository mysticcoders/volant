import Foundation

/// What a `break` or `breaks` query in the launcher asks for.
public enum BreakCommand: Equatable, Sendable {
    /// The bare query, or one that names nothing else: list the Break rows.
    case menu
    case now, skip, pause, resume, on, off, end

    /// The launcher words that open the Break rows.
    public static let keywords: Set<String> = ["break", "breaks"]

    /// The command for a launcher query, or nil when the query doesn't start with `break` or
    /// `breaks`. Keywords are matched without regard to case.
    public static func parse(_ query: String) -> BreakCommand? {
        let words = query.split(whereSeparator: \.isWhitespace).map { $0.lowercased() }
        guard let first = words.first, keywords.contains(first) else { return nil }
        guard words.count == 2 else { return .menu }
        switch words[1] {
        case "now", "start", "take": return .now
        case "skip": return .skip
        case "pause", "snooze": return .pause
        case "resume", "continue": return .resume
        case "on", "enable": return .on
        case "off", "disable": return .off
        case "end", "stop", "done": return .end
        default: return .menu
        }
    }
}
