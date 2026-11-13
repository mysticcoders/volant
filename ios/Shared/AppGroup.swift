import Foundation

/// What the app, its widgets and its share extension exchange through the App Group container:
/// a snapshot of the notes list for widgets and Shortcuts, and an inbox for notes saved while
/// iCloud could not be reached.
enum AppGroup {
    static let id = "group.com.mysticcoders.volant"

    static var container: URL? { FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: id) }
    static var snapshotURL: URL? { container?.appendingPathComponent("notes-snapshot.json") }
    static var inbox: URL? { container?.appendingPathComponent("Inbox", isDirectory: true) }

    /// The last snapshot the app wrote, or an empty one before the app has run.
    static func readSnapshot() -> NotesSnapshot {
        guard let url = snapshotURL, let data = try? Data(contentsOf: url),
              let snapshot = try? JSONDecoder().decode(NotesSnapshot.self, from: data) else { return .empty }
        return snapshot
    }

    /// Writes the snapshot when it differs from the stored one. Returns whether anything changed.
    @discardableResult
    static func writeSnapshot(_ snapshot: NotesSnapshot) -> Bool {
        guard let url = snapshotURL, snapshot != readSnapshot(),
              let data = try? JSONEncoder().encode(snapshot) else { return false }
        return (try? data.write(to: url, options: .atomic)) != nil
    }
}

/// The notes list as widgets and Shortcuts see it: titles and dates for every note, with previews
/// only for the few shown in widgets. Note text itself never goes into the App Group.
struct NotesSnapshot: Codable, Equatable {
    struct Item: Codable, Equatable, Hashable, Identifiable {
        let id: String
        let title: String
        let preview: String
        let modified: Date
        let pinned: Bool
    }

    var recent: [Item]
    var all: [Item]
    var inICloud: Bool

    static let empty = NotesSnapshot(recent: [], all: [], inICloud: false)
    static let recentLimit = 8
}

/// Writes a new note from outside the app. The note goes straight into the iCloud notes folder
/// when this process can reach it, so it appears on the Mac at once; otherwise it waits in the
/// App Group inbox until the app next opens and moves it into the notes folder.
enum NoteWriter {
    static let containerID = "iCloud.com.mysticcoders.volant"

    /// A name in the notes store's scheme: the day for people, a random suffix for uniqueness.
    static func fileName(now: Date = Date()) -> String {
        "\(now.formatted(.iso8601.year().month().day()))-\(UUID().uuidString.prefix(8)).md"
    }

    /// Markdown for a title and body: the title as a heading when there is one.
    static func markdown(title: String, body: String) -> String {
        let title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let body = body.trimmingCharacters(in: .whitespacesAndNewlines)
        if title.isEmpty { return body + "\n" }
        return body.isEmpty ? "# \(title)\n" : "# \(title)\n\n\(body)\n"
    }

    /// Saves the text as a new note and returns its file name. Call off the main thread: finding the
    /// iCloud container can block.
    static func save(_ text: String) throws -> (id: String, inICloud: Bool) {
        let name = fileName()
        if let container = FileManager.default.url(forUbiquityContainerIdentifier: containerID) {
            let folder = container.appendingPathComponent("Documents/Notes", isDirectory: true)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try coordinatedWrite(text, to: folder.appendingPathComponent(name))
            return (name, true)
        }
        guard let inbox = AppGroup.inbox else { throw CocoaError(.fileNoSuchFile) }
        try FileManager.default.createDirectory(at: inbox, withIntermediateDirectories: true)
        try text.write(to: inbox.appendingPathComponent(name), atomically: true, encoding: .utf8)
        return (name, false)
    }

    private static func coordinatedWrite(_ text: String, to url: URL) throws {
        var coordinationError: NSError?
        var writeError: Error?
        NSFileCoordinator().coordinate(writingItemAt: url, options: .forReplacing, error: &coordinationError) { target in
            do { try text.write(to: target, atomically: true, encoding: .utf8) } catch { writeError = error }
        }
        if let error = writeError ?? coordinationError { throw error }
    }
}

/// Places in the app that widgets, controls and Shortcuts can open, as `volant://` links.
enum DeepLink: Equatable {
    case newNote
    case note(String)
    case search
    case tool(String)

    static let scheme = "volant"

    var url: URL {
        switch self {
        case .newNote: URL(string: "volant://new")!
        case .note(let id): URL(string: "volant://note/\(id.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? id)")!
        case .search: URL(string: "volant://search")!
        case .tool(let name): URL(string: "volant://tool/\(name)")!
        }
    }

    init?(_ url: URL) {
        guard url.scheme == Self.scheme else { return nil }
        let value = url.pathComponents.dropFirst().first
        switch url.host() {
        case "new": self = .newNote
        case "search": self = .search
        case "note": guard let value else { return nil }; self = .note(value)
        case "tool": guard let value else { return nil }; self = .tool(value)
        default: return nil
        }
    }
}

/// Hands a deep link from an App Intent running in the app's process to the app's views. A link
/// posted before the views exist, on a cold launch, waits in `pending` until they read it.
@MainActor
enum DeepLinkCenter {
    static let notification = Notification.Name("VolantDeepLink")
    static var pending: DeepLink?

    static func post(_ link: DeepLink) {
        pending = link
        NotificationCenter.default.post(name: notification, object: nil)
    }

    static func take() -> DeepLink? {
        defer { pending = nil }
        return pending
    }
}
