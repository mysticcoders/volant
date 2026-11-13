import Foundation
import Combine
import UIKit
import VolantCore

/// Snippets and quicklinks shared with the Mac through the iCloud key-value store its settings sync
/// uses (`settings.snippets`, `settings.quicklinks`, each a SettingsSync envelope). Edits here are
/// written back as a newer envelope, which a Mac with sync on adopts like a change from another Mac.
/// Entries are edited as raw JSON objects, so fields this app does not know survive the round trip.
@MainActor
final class MacSettings: ObservableObject {
    enum State: Equatable { case loading, unavailable, empty, ready }

    @Published private(set) var snippets: [Snippet] = []
    @Published private(set) var quicklinks: [Quicklink] = []
    @Published private(set) var updated: Date?
    @Published private(set) var state: State = .loading
    private let store = NSUbiquitousKeyValueStore.default
    private var rawSnippets: [[String: Any]] = []
    private var rawLinks: [[String: Any]] = []
    private var observer: NSObjectProtocol?

    init() {
        if let path = UserDefaults.standard.string(forKey: "fixtureMacSettings") {
            loadFixture(URL(fileURLWithPath: path))
            return
        }
        observer = NotificationCenter.default.addObserver(forName: NSUbiquitousKeyValueStore.didChangeExternallyNotification,
                                                          object: store, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.load() }
        }
        store.synchronize()
        load()
    }

    /// Reads both keys. An account without iCloud reads as unavailable; a store the Mac never wrote reads as empty.
    func load() {
        guard FileManager.default.ubiquityIdentityToken != nil else { state = .unavailable; return }
        let snippetEntry = SettingsSync.Entry(propertyList: store.object(forKey: "settings.snippets"))
        let linkEntry = SettingsSync.Entry(propertyList: store.object(forKey: "settings.quicklinks"))
        let decoder = JSONDecoder()
        snippets = snippetEntry.flatMap { try? decoder.decode([Snippet].self, from: $0.value) } ?? []
        quicklinks = linkEntry.flatMap { try? decoder.decode([Quicklink].self, from: $0.value) } ?? []
        rawSnippets = snippetEntry.flatMap { try? JSONSerialization.jsonObject(with: $0.value) as? [[String: Any]] } ?? snippets.map(Self.object)
        rawLinks = linkEntry.flatMap { try? JSONSerialization.jsonObject(with: $0.value) as? [[String: Any]] } ?? quicklinks.map(Self.object)
        if rawSnippets.count != snippets.count { rawSnippets = snippets.map(Self.object) }
        if rawLinks.count != quicklinks.count { rawLinks = quicklinks.map(Self.object) }
        updated = [snippetEntry?.modified, linkEntry?.modified].compactMap { $0 }.max()
        state = snippetEntry == nil && linkEntry == nil ? .empty : .ready
    }

    /// Fictional snippets and quicklinks from a JSON file, for simulator screenshots (`-fixtureMacSettings <path>`).
    /// The iCloud store is never read or written in this mode.
    private func loadFixture(_ url: URL) {
        struct Fixture: Decodable { let snippets: [Snippet]; let quicklinks: [Quicklink] }
        guard let data = try? Data(contentsOf: url), let fixture = try? JSONDecoder().decode(Fixture.self, from: data) else { return }
        snippets = fixture.snippets
        quicklinks = fixture.quicklinks
        rawSnippets = snippets.map(Self.object)
        rawLinks = quicklinks.map(Self.object)
        updated = Date().addingTimeInterval(-300)
        state = .ready
    }

    /// Whether edits can be sent: iCloud is signed in and the store has been read.
    var canEdit: Bool { state == .ready || state == .empty }

    /// Adds or replaces a snippet. `index` is its position in `snippets`, or nil for a new one.
    func save(_ snippet: Snippet, at index: Int?) {
        var list = rawSnippets
        var object = index.map { list[$0] } ?? [:]
        object["name"] = snippet.name
        object["keyword"] = snippet.keyword
        object["body"] = snippet.body
        if let index { list[index] = object } else { list.append(object) }
        write("snippets", list)
    }

    func deleteSnippet(at index: Int) {
        var list = rawSnippets
        list.remove(at: index)
        write("snippets", list)
    }

    /// Adds or replaces a quicklink. `index` is its position in `quicklinks`, or nil for a new one.
    func save(_ link: Quicklink, at index: Int?) {
        var list = rawLinks
        var object = index.map { list[$0] } ?? [:]
        object["name"] = link.name
        object["url"] = link.url
        if let index { list[index] = object } else { list.append(object) }
        write("quicklinks", list)
    }

    func deleteQuicklink(at index: Int) {
        var list = rawLinks
        list.remove(at: index)
        write("quicklinks", list)
    }

    /// Stores the list as a canonical, newer envelope, then reads it back. A list that would not
    /// decode as the Mac expects is never sent.
    private func write(_ key: String, _ list: [[String: Any]]) {
        guard let value = try? SettingsSync.canonical(list),
              (key == "snippets" ? (try? JSONDecoder().decode([Snippet].self, from: value)) != nil
                                 : (try? JSONDecoder().decode([Quicklink].self, from: value)) != nil) else { return }
        store.set(SettingsSync.Entry(value: value, modified: Date()).propertyList, forKey: "settings." + key)
        store.synchronize()
        load()
    }

    private static func object(_ snippet: Snippet) -> [String: Any] {
        ["name": snippet.name, "keyword": snippet.keyword, "body": snippet.body]
    }

    private static func object(_ link: Quicklink) -> [String: Any] {
        ["name": link.name, "url": link.url]
    }

    /// Asks iCloud for the latest values, for pull to refresh.
    func refresh() {
        store.synchronize()
        load()
    }

    /// A snippet's text with the Mac's placeholders filled in the same way the Mac expands them.
    static func expand(_ body: String, now: Date = Date()) -> String {
        var s = body
        s = s.replacingOccurrences(of: "{date}", with: now.formatted(date: .abbreviated, time: .omitted))
        s = s.replacingOccurrences(of: "{isodate}", with: now.formatted(.iso8601.year().month().day()))
        s = s.replacingOccurrences(of: "{time}", with: now.formatted(date: .omitted, time: .shortened))
        s = s.replacingOccurrences(of: "{datetime}", with: now.formatted(date: .abbreviated, time: .shortened))
        s = s.replacingOccurrences(of: "{uuid}", with: UUID().uuidString)
        if s.contains("{clipboard}") { s = s.replacingOccurrences(of: "{clipboard}", with: UIPasteboard.general.string ?? "") }
        return s
    }
}
