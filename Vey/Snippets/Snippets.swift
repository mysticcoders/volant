import AppKit

struct Snippet: Codable, Hashable {
    var name: String
    var keyword: String
    var body: String
}

/// Expands placeholders at copy time. No paste; the result lands on the clipboard.
enum SnippetExpander {
    static func expand(_ body: String, now: Date = Date(), clipboard: String? = nil) -> String {
        var s = body
        s = s.replacingOccurrences(of: "{date}", with: now.formatted(date: .abbreviated, time: .omitted))
        s = s.replacingOccurrences(of: "{isodate}", with: now.formatted(.iso8601.year().month().day()))
        s = s.replacingOccurrences(of: "{time}", with: now.formatted(date: .omitted, time: .shortened))
        s = s.replacingOccurrences(of: "{datetime}", with: now.formatted(date: .abbreviated, time: .shortened))
        s = s.replacingOccurrences(of: "{uuid}", with: UUID().uuidString)
        s = s.replacingOccurrences(of: "{clipboard}", with: clipboard ?? NSPasteboard.general.string(forType: .string) ?? "")
        return s
    }

    static func search(_ snippets: [Snippet], _ term: String, limit: Int = 6) -> [Snippet] {
        let t = term.lowercased().trimmingCharacters(in: .whitespaces)
        guard !t.isEmpty else { return Array(snippets.prefix(limit)) }
        let exact = snippets.filter { $0.keyword.lowercased() == t }
        let rest = snippets.filter { !exact.contains($0) && ($0.name.lowercased().contains(t) || $0.keyword.lowercased().hasPrefix(t)) }
        return Array((exact + rest).prefix(limit))
    }
}
