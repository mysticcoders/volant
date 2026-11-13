import Foundation

/// What a `focus` query in the launcher asks for.
public enum FocusCommand: Equatable, Sendable {
    /// How long a session started from the launcher runs.
    public enum Length: Equatable, Sendable {
        case remembered
        case minutes(Int)
    }

    /// The bare `focus` query, or one that names nothing else: list the Focus rows.
    case menu
    /// `focus 25m write the newsletter`: start with the remembered block list. A nil goal keeps the
    /// remembered one.
    case start(Length, goal: String?)
    case pause, resume, complete, end, edit

    /// The command for a launcher query, or nil when the query doesn't start with `focus`.
    /// Keywords are matched without regard to case; a goal keeps the owner's own case.
    public static func parse(_ query: String) -> FocusCommand? {
        let words = query.split(whereSeparator: \.isWhitespace).map(String.init)
        guard let first = words.first, first.lowercased() == "focus" else { return nil }
        let rest = Array(words.dropFirst())
        guard let head = rest.first else { return .menu }
        if rest.count == 1, let action = action(head.lowercased()) { return action }
        if let minutes = minutes(head) {
            let goal = rest.dropFirst().joined(separator: " ")
            return .start(.minutes(minutes), goal: goal.isEmpty ? nil : goal)
        }
        return .start(.remembered, goal: rest.joined(separator: " "))
    }

    /// A length such as `25`, `25m`, `25min`, `1h` or `1h30m`, within a session's limits.
    public static func minutes(_ token: String) -> Int? {
        let text = token.lowercased()
        var total = 0
        var number = ""
        var unitSeen = false
        var index = text.startIndex
        while index < text.endIndex {
            let character = text[index]
            if character.isASCII, character.isNumber {
                number.append(character)
                index = text.index(after: index)
                continue
            }
            let remainder = text[index...]
            guard let value = Int(number) else { return nil }
            if remainder.hasPrefix("h") {
                total += value * 60
                index = text.index(after: index)
            } else if remainder.hasPrefix("min") {
                total += value
                index = text.index(index, offsetBy: 3)
            } else if remainder.hasPrefix("m") {
                total += value
                index = text.index(after: index)
            } else {
                return nil
            }
            number = ""
            unitSeen = true
        }
        if !number.isEmpty {
            guard let value = Int(number), !unitSeen || total > 0 else { return nil }
            total += value
        }
        guard total >= 1, total <= FocusSetup.maximumMinutes else { return nil }
        return total
    }

    private static func action(_ word: String) -> FocusCommand? {
        switch word {
        case "pause": return .pause
        case "resume", "continue": return .resume
        case "complete", "done", "finish": return .complete
        case "end", "stop", "off", "cancel": return .end
        case "edit": return .edit
        default: return nil
        }
    }
}
