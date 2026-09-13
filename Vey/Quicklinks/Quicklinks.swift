import AppKit

struct Quicklink: Codable, Hashable {
    var name: String
    var url: String
}

/// Opens only http, https and mailto. `{query}` in the template is percent-encoded from the typed text.
enum QuicklinkResolver {
    static let allowedSchemes: Set<String> = ["http", "https", "mailto"]

    static func url(for link: Quicklink, query: String) -> URL? {
        let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        let text = link.url.replacingOccurrences(of: "{query}", with: encoded)
        guard let url = URL(string: text), let scheme = url.scheme?.lowercased(), allowedSchemes.contains(scheme) else { return nil }
        return url
    }

    static func needsQuery(_ link: Quicklink) -> Bool { link.url.contains("{query}") }

    static func search(_ links: [Quicklink], _ term: String, limit: Int = 5) -> [Quicklink] {
        let t = term.lowercased()
        guard !t.isEmpty else { return [] }
        return Array(links.filter { $0.name.lowercased().hasPrefix(t) || $0.name.lowercased().contains(" " + t) }.prefix(limit))
    }

    static func open(_ url: URL) { NSWorkspace.shared.open(url) }
}
