import Foundation

/// A short fact a list extension shows at the trailing edge of a row, such as a story's points, its
/// comment count or the site it links to. The extension names a `symbol` from a fixed set that Volant
/// draws itself and gives the `text`; badges replace the extension's name at the row's end.
public struct ExtensionItemBadge: Codable, Hashable, Sendable {
    public static let maximumPerItem = 3
    public static let maximumTextLength = 32
    public var symbol: String?
    public var text: String
    public init(symbol: String? = nil, text: String) { self.symbol = symbol; self.text = text }

    /// Trims the text to one line of at most 32 characters, dropping an empty badge, and drops a symbol
    /// Volant does not know while keeping the text.
    func sanitized() -> ExtensionItemBadge? {
        let text = String(text.split(whereSeparator: \.isNewline).joined(separator: " ").trimmingCharacters(in: .whitespaces).prefix(Self.maximumTextLength))
        guard !text.isEmpty else { return nil }
        return ExtensionItemBadge(symbol: symbol.flatMap(Symbol.init(rawValue:))?.rawValue, text: text)
    }

    /// The icons a badge may carry, each drawn as a monochrome SF Symbol.
    public enum Symbol: String, CaseIterable, Sendable {
        case points, comments, site, author, time

        public var systemName: String {
            switch self {
            case .points: "arrow.up"
            case .comments: "bubble.left"
            case .site: "globe"
            case .author: "person"
            case .time: "clock"
            }
        }

        /// What VoiceOver says before the badge's text.
        public var spokenName: String {
            switch self {
            case .points: "Points"
            case .comments: "Comments"
            case .site: "Site"
            case .author: "Author"
            case .time: "Time"
            }
        }
    }
}
