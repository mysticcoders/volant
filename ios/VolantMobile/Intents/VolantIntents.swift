import AppIntents
import UIKit
import VolantCore

/// A note as Shortcuts sees it, identified by its file name and found through the App Group snapshot.
struct NoteEntity: AppEntity {
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Volant Note"
    static let defaultQuery = NoteEntityQuery()

    let id: String
    let title: String
    let modified: Date

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(title)", subtitle: "\(modified.formatted(.relative(presentation: .named)))")
    }

    init(_ item: NotesSnapshot.Item) {
        id = item.id
        title = item.title
        modified = item.modified
    }
}

struct NoteEntityQuery: EntityStringQuery {
    func entities(for identifiers: [String]) async throws -> [NoteEntity] {
        let all = AppGroup.readSnapshot().all
        return identifiers.compactMap { id in all.first { $0.id == id }.map(NoteEntity.init) }
    }

    func entities(matching string: String) async throws -> [NoteEntity] {
        AppGroup.readSnapshot().all.filter { $0.title.localizedCaseInsensitiveContains(string) }.prefix(20).map(NoteEntity.init)
    }

    func suggestedEntities() async throws -> [NoteEntity] {
        AppGroup.readSnapshot().recent.map(NoteEntity.init)
    }
}

/// A snippet from the Mac's settings sync.
struct SnippetEntity: AppEntity {
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Volant Snippet"
    static let defaultQuery = SnippetEntityQuery()

    let id: String
    let name: String
    let keyword: String
    let body: String

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(name)", subtitle: keyword.isEmpty ? nil : "\(keyword)")
    }

    init(_ snippet: Snippet) {
        id = snippet.name + "\u{0}" + snippet.keyword
        name = snippet.name
        keyword = snippet.keyword
        body = snippet.body
    }
}

struct SnippetEntityQuery: EntityStringQuery {
    @MainActor private var snippets: [SnippetEntity] { MacSettingsReader.snippets().map(SnippetEntity.init) }

    func entities(for identifiers: [String]) async throws -> [SnippetEntity] {
        await MainActor.run { snippets.filter { identifiers.contains($0.id) } }
    }

    func entities(matching string: String) async throws -> [SnippetEntity] {
        await MainActor.run { snippets.filter { $0.name.localizedCaseInsensitiveContains(string) || $0.keyword.localizedCaseInsensitiveContains(string) } }
    }

    func suggestedEntities() async throws -> [SnippetEntity] {
        await MainActor.run { snippets }
    }
}

/// A quicklink from the Mac's settings sync.
struct QuicklinkEntity: AppEntity {
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Volant Quicklink"
    static let defaultQuery = QuicklinkEntityQuery()

    let id: String
    let name: String
    let url: String

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(name)", subtitle: "\(Quicklink(name: name, url: url).displayHost)")
    }

    init(_ link: Quicklink) {
        id = link.id
        name = link.name
        url = link.url
    }
}

struct QuicklinkEntityQuery: EntityStringQuery {
    @MainActor private var links: [QuicklinkEntity] { MacSettingsReader.quicklinks().map(QuicklinkEntity.init) }

    func entities(for identifiers: [String]) async throws -> [QuicklinkEntity] {
        await MainActor.run { links.filter { identifiers.contains($0.id) } }
    }

    func entities(matching string: String) async throws -> [QuicklinkEntity] {
        await MainActor.run { links.filter { $0.name.localizedCaseInsensitiveContains(string) } }
    }

    /// The first quicklinks only: iOS turns each suggestion into its own "Open … with Volant" tile in
    /// Shortcuts and Siri, so the list is capped. Searching the picker still finds every quicklink.
    func suggestedEntities() async throws -> [QuicklinkEntity] {
        await MainActor.run { Array(links.prefix(Self.suggestionLimit)) }
    }

    static let suggestionLimit = 10
}

/// Reads the Mac's synced snippets and quicklinks without the app's views, for intents run in the background.
@MainActor
enum MacSettingsReader {
    static func snippets() -> [Snippet] { decode("settings.snippets") ?? [] }
    static func quicklinks() -> [Quicklink] { decode("settings.quicklinks") ?? [] }

    private static func decode<T: Decodable>(_ key: String) -> T? {
        let store = NSUbiquitousKeyValueStore.default
        store.synchronize()
        guard let entry = SettingsSync.Entry(propertyList: store.object(forKey: key)) else { return nil }
        return try? JSONDecoder().decode(T.self, from: entry.value)
    }
}

/// Saves a note without opening Volant: the text becomes the body, with an optional title heading.
struct CreateNoteIntent: AppIntent {
    static let title: LocalizedStringResource = "Create Note"
    static let description = IntentDescription("Saves text as a new Volant note, synced through iCloud.")

    @Parameter(title: "Text", inputOptions: String.IntentInputOptions(multiline: true))
    var text: String

    @Parameter(title: "Title")
    var noteTitle: String?

    static var parameterSummary: some ParameterSummary {
        Summary("Create a note with \(\.$text)") { \.$noteTitle }
    }

    func perform() async throws -> some IntentResult & ReturnsValue<NoteEntity> & ProvidesDialog {
        let markdown = NoteWriter.markdown(title: noteTitle ?? "", body: text)
        let saved = try await Task.detached { try NoteWriter.save(markdown) }.value
        let title = Note.summary(of: markdown).heading
        let entity = NoteEntity(.init(id: saved.id, title: title.isEmpty ? String(localized: "Untitled") : title, preview: "", modified: Date(), pinned: false))
        return .result(value: entity, dialog: "Saved to Volant.")
    }
}

/// Opens a note in Volant.
struct OpenNoteIntent: AppIntent {
    static let title: LocalizedStringResource = "Open Note"
    static let description = IntentDescription("Opens a note in Volant.")
    static let openAppWhenRun = true

    @Parameter(title: "Note")
    var note: NoteEntity

    @MainActor
    func perform() async throws -> some IntentResult {
        DeepLinkCenter.post(.note(note.id))
        return .result()
    }
}

/// Copies a snippet with its placeholders filled in, and returns the text for later actions.
struct CopySnippetIntent: AppIntent {
    static let title: LocalizedStringResource = "Copy Snippet"
    static let description = IntentDescription("Copies one of your Volant snippets, with dates and other placeholders filled in.")

    @Parameter(title: "Snippet")
    var snippet: SnippetEntity

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<String> & ProvidesDialog {
        let text = MacSettings.expand(snippet.body)
        UIPasteboard.general.string = text
        return .result(value: text, dialog: "Copied \(snippet.name).")
    }
}

/// Opens a quicklink, filling in its search text when it takes one.
struct OpenQuicklinkIntent: AppIntent {
    static let title: LocalizedStringResource = "Open Quicklink"
    static let description = IntentDescription("Opens one of your Volant quicklinks. Links with a search slot use the text you give.")

    @Parameter(title: "Quicklink")
    var link: QuicklinkEntity

    @Parameter(title: "Search Text")
    var query: String?

    func perform() async throws -> some IntentResult & OpensIntent {
        guard let url = Quicklink(name: link.name, url: link.url).resolvedURL(query: query ?? "") else {
            throw $link.needsValueError("That quicklink can’t be opened here. Choose another.")
        }
        return .result(opensIntent: OpenURLIntent(url))
    }
}

/// Answers a calculation with the Mac launcher's calculator. Intent descriptions shown to Siri and
/// Shortcuts must not name a platform such as Mac or iPhone (App Store check ITMS-90626).
struct CalculateIntent: AppIntent {
    static let title: LocalizedStringResource = "Calculate"
    static let description = IntentDescription("Answers math, unit conversions, dates and time zones with Volant’s calculator.")

    @Parameter(title: "Calculation")
    var expression: String

    func perform() async throws -> some IntentResult & ReturnsValue<String> & ProvidesDialog {
        guard let answer = CalculationAnswer.answers(for: expression).first else {
            throw $expression.needsValueError("Volant couldn’t answer that. Try something like 5 km in mi.")
        }
        return .result(value: answer.copyText, dialog: "\(answer.input) = \(answer.result)")
    }
}

/// Phrases that work in Siri and Spotlight without setting up a shortcut. Snippets get one tile that
/// asks which snippet; quicklinks get a tile each, up to `QuicklinkEntityQuery.suggestionLimit`.
struct VolantShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: NewNoteInAppIntent(), phrases: ["New note in \(.applicationName)", "Start a \(.applicationName) note"],
                    shortTitle: "New Note", systemImageName: "square.and.pencil")
        AppShortcut(intent: CreateNoteIntent(), phrases: ["Save a note to \(.applicationName)"],
                    shortTitle: "Create Note", systemImageName: "note.text.badge.plus")
        AppShortcut(intent: OpenNoteIntent(), phrases: ["Open \(\.$note) in \(.applicationName)"],
                    shortTitle: "Open Note", systemImageName: "note.text")
        AppShortcut(intent: CopySnippetIntent(), phrases: ["Copy a snippet with \(.applicationName)", "Copy a \(.applicationName) snippet"],
                    shortTitle: "Copy Snippet", systemImageName: "text.quote")
        AppShortcut(intent: OpenQuicklinkIntent(), phrases: ["Open \(\.$link) with \(.applicationName)", "Open a \(.applicationName) quicklink"],
                    shortTitle: "Open Quicklink", systemImageName: "bolt.fill")
        AppShortcut(intent: CalculateIntent(), phrases: ["Calculate with \(.applicationName)"],
                    shortTitle: "Calculate", systemImageName: "plus.forwardslash.minus")
    }
}
