import Foundation

/// One release's notes, parsed from the Markdown in docs/releases/<version>.md that also becomes the
/// GitHub release body. `## ` headings start sections, `- ` lines are items (indented lines continue
/// the item above), and any other paragraph is kept as a closing note. Pull request references such
/// as "(#224, #225)" are dropped because they mean nothing inside the app; inline Markdown stays.
public struct ReleaseNotes: Equatable, Sendable {
    public struct Section: Equatable, Sendable {
        public let title: String
        public let items: [String]
    }

    public let version: String
    public let sections: [Section]
    public let notes: [String]

    public init(version: String, markdown: String) {
        self.version = version
        var sections: [Section] = []
        var notes: [String] = []
        var title: String?
        var items: [String] = []
        func closeSection() {
            if let title, !items.isEmpty { sections.append(Section(title: title, items: items)) }
            title = nil
            items = []
        }
        for raw in markdown.components(separatedBy: .newlines) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.isEmpty { continue }
            if line.hasPrefix("## ") {
                closeSection()
                title = String(line.dropFirst(3)).trimmingCharacters(in: .whitespaces)
            } else if line.hasPrefix("- ") || line.hasPrefix("* ") {
                items.append(Self.clean(String(line.dropFirst(2))))
            } else if raw.hasPrefix(" ") || raw.hasPrefix("\t"), let last = items.popLast() {
                items.append(Self.clean(last + " " + line))
            } else if line.hasPrefix("#") {
                continue
            } else {
                closeSection()
                notes.append(Self.clean(line))
            }
        }
        closeSection()
        self.sections = sections
        self.notes = notes
    }

    /// Whether `version` is newer than `other`, comparing dotted numbers so 0.3.10 follows 0.3.9.
    public static func isNewer(_ version: String, than other: String) -> Bool {
        let lhs = version.split(separator: ".").map { Int($0) ?? 0 }
        let rhs = other.split(separator: ".").map { Int($0) ?? 0 }
        for index in 0..<max(lhs.count, rhs.count) {
            let left = index < lhs.count ? lhs[index] : 0
            let right = index < rhs.count ? rhs[index] : 0
            if left != right { return left > right }
        }
        return false
    }

    /// Reads every `<version>.md` in a folder, newest version first. Unreadable files are skipped.
    public static func load(from directory: URL) -> [ReleaseNotes] {
        let files = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
        return files.filter { $0.pathExtension == "md" }
            .compactMap { file -> ReleaseNotes? in
                guard let text = try? String(contentsOf: file, encoding: .utf8) else { return nil }
                return ReleaseNotes(version: file.deletingPathExtension().lastPathComponent, markdown: text)
            }
            .sorted { isNewer($0.version, than: $1.version) }
    }

    private static let references = try! NSRegularExpression(pattern: #"\s*\((?:#\d+(?:,\s*)?)+\)"#)

    private static func clean(_ text: String) -> String {
        let range = NSRange(text.startIndex..., in: text)
        return references.stringByReplacingMatches(in: text, range: range, withTemplate: "")
            .trimmingCharacters(in: .whitespaces)
    }
}
