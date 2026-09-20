import Foundation

public struct EmojiEntry: Hashable {
    public let symbol: String
    public let name: String

    public init(symbol: String, name: String) {
        self.symbol = symbol
        self.name = name
    }
}

/// Emoji names from the bundled Unicode-derived list. Loaded once, searched by substring and word prefix.
public enum EmojiIndex {
    public static let all: [EmojiEntry] = {
        guard let url = Bundle.main.url(forResource: "emoji", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let raw = try? JSONSerialization.jsonObject(with: data) as? [[String]] else { return [] }
        let entries = raw.compactMap { row -> EmojiEntry? in
            guard row.count == 2 else { return nil }
            return catalogEntry(symbol: row[0], name: row[1])
        }
        let common = ["😀", "😃", "😄", "😁", "😆", "😅", "😂", "🙂", "😉", "😊", "😍", "🥰", "😘", "😎", "🤩", "🥳", "🤔", "🤗", "😴", "🤓", "👍", "❤️", "🎉", "🚀", "☕"]
        let bySymbol = Dictionary(entries.map { ($0.symbol, $0) }, uniquingKeysWith: { first, _ in first })
        let preferred = common.compactMap { bySymbol[$0] }
        let preferredSymbols = Set(preferred.map(\.symbol))
        return preferred + entries.filter { !preferredSymbols.contains($0.symbol) }
    }()

    /// The legacy catalog also includes individual regional indicators and text symbols.
    /// Only offer complete emoji, and request emoji presentation for text-default scalars.
    public static func catalogEntry(symbol: String, name: String) -> EmojiEntry? {
        let scalars = symbol.unicodeScalars
        guard scalars.contains(where: { $0.properties.isEmoji }) else { return nil }
        if scalars.count == 1, let scalar = scalars.first {
            guard !(0x1F1E6...0x1F1FF).contains(scalar.value), !(0x1F3FB...0x1F3FF).contains(scalar.value),
                  !"0123456789#*".unicodeScalars.contains(scalar) else { return nil }
            return EmojiEntry(symbol: symbol + (scalar.properties.isEmojiPresentation ? "" : "\u{FE0F}"), name: name)
        }
        return EmojiEntry(symbol: symbol, name: name)
    }

    public static func search(_ term: String, limit: Int = 12, entries: [EmojiEntry] = all) -> [EmojiEntry] {
        guard limit > 0 else { return [] }
        let term = term.lowercased().trimmingCharacters(in: .whitespaces)
        guard !term.isEmpty else { return limit >= entries.count ? entries : Array(entries.prefix(limit)) }
        var starts: [EmojiEntry] = []
        var contains: [EmojiEntry] = []
        for entry in entries {
            if entry.name.split(separator: " ").contains(where: { $0.hasPrefix(term) }) {
                if starts.count < limit { starts.append(entry) }
            } else if contains.count < limit && entry.name.contains(term) {
                contains.append(entry)
            }
        }
        starts.append(contentsOf: contains.prefix(max(0, limit - starts.count)))
        return starts
    }
}
