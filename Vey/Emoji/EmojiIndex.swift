import Foundation

struct EmojiEntry: Hashable { let symbol: String; let name: String }

/// Emoji names from the bundled Unicode-derived list. Loaded once, searched by substring and word prefix.
enum EmojiIndex {
    static let all: [EmojiEntry] = {
        guard let url = Bundle.main.url(forResource: "emoji", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let raw = try? JSONSerialization.jsonObject(with: data) as? [[String]] else { return [] }
        return raw.compactMap { $0.count == 2 ? EmojiEntry(symbol: $0[0], name: $0[1]) : nil }
    }()

    static func search(_ term: String, limit: Int = 12) -> [EmojiEntry] {
        let t = term.lowercased().trimmingCharacters(in: .whitespaces)
        guard !t.isEmpty else { return [] }
        let starts = all.filter { $0.name.split(separator: " ").contains { $0.hasPrefix(t) } }
        let contains = all.filter { $0.name.contains(t) && !starts.contains($0) }
        return Array((starts + contains).prefix(limit))
    }
}
