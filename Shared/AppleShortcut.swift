import Foundation

struct AppleShortcut: Codable, Hashable, Identifiable {
    let id: String
    let name: String

    static func decodeListing(_ data: Data) throws -> [Self] {
        guard data.count <= 2_000_000, let text = String(data: data, encoding: .utf8) else { throw CocoaError(.fileReadCorruptFile) }
        var seen = Set<String>()
        return try text.split(separator: "\n").map { line in
            guard let start = line.range(of: " (", options: .backwards), line.hasSuffix(")"),
                  let uuid = UUID(uuidString: String(line[start.upperBound..<line.index(before: line.endIndex)])) else { throw CocoaError(.fileReadCorruptFile) }
            let name = String(line[..<start.lowerBound])
            guard !name.isEmpty else { throw CocoaError(.fileReadCorruptFile) }
            return Self(id: uuid.uuidString, name: name)
        }.filter { seen.insert($0.id).inserted }.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    static func queryTerm(_ query: String) -> String? {
        let value = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        for prefix in ["apple shortcuts", "apple shortcut", "shortcuts", "shortcut"] {
            if value == prefix { return "" }
            if value.hasPrefix(prefix + " ") { return String(value.dropFirst(prefix.count + 1)) }
        }
        return nil
    }
}
