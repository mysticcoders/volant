import Foundation
import VolantCore

/// The tools Volant offers AI apps, built from the app's own stores so each tool runs the same code
/// the launcher and Settings use: notes through `NotesStore` and its save and retry rules, snippets and
/// quicklinks through `LauncherEntries`' validated, stale-checked patches. Write tools are listed only
/// while their switch is on. Arguments and results are never logged.
struct MCPToolbox {
    /// The longest text one call returns or accepts.
    static let maximumText = 100_000

    let notes: NotesStore
    let configURL: URL
    let breakHistoryURL: URL
    /// The Breaks and Focus status lines the launcher shows, read on the main queue.
    var breakStatus: @MainActor () -> (enabled: Bool, status: String) = { (false, "") }
    var focusStatus: @MainActor () -> (goal: String, paused: Bool, time: String)? = { nil }
    /// Reloads the configuration after a snippet or quicklink was added.
    var configChanged: @MainActor () -> Void = {}

    func tools(_ preferences: MCPPreferences) -> [MCPTool] {
        var tools = [calculate, searchNotes, readNote, listSnippets, listQuicklinks, breakStatusTool, focusStatusTool]
        if preferences.writesNotes { tools += [createNote, appendToNote] }
        if preferences.writesSnippets { tools.append(addSnippet) }
        if preferences.writesQuicklinks { tools.append(addQuicklink) }
        return tools
    }

    private var calculate: MCPTool {
        MCPTool(name: "calculate", title: "Calculate",
                description: "Volant's calculator: arithmetic, percentages, unit and kitchen conversions, number bases, colors, dates and durations, and times across time zones, such as `5 km in miles`, `3pm Tokyo in New York` or `90 days from today`. Returns every answer Volant finds. Currency isn't included.",
                inputSchema: MCPTool.schema(["query": MCPTool.string("What to calculate, as you would type it in Volant's launcher.", maxLength: 500)], required: ["query"]),
                readOnly: true, idempotent: true) { arguments in
            guard let query = arguments["query"]?.string?.trimmingCharacters(in: .whitespacesAndNewlines), !query.isEmpty, query.count <= 500 else {
                return .failure("Give a query of 1 to 500 characters.")
            }
            let answers = CalculationAnswer.answers(for: query)
            guard !answers.isEmpty else {
                return .failure("Volant couldn't calculate that. Try a conversion like `5 km in miles`, a time like `3pm Tokyo in New York`, or arithmetic.")
            }
            return .data(.object(["answers": .array(answers.map { answer in
                var fields: [String: MCPValue] = ["input": .string(answer.input), "result": .string(answer.result)]
                if let detail = answer.resultDetail { fields["detail"] = .string(detail) }
                return .object(fields)
            })]))
        }
    }

    private var searchNotes: MCPTool {
        MCPTool(name: "search_notes", title: "Search notes",
                description: "Searches the owner's Volant notes (Markdown files) by their full text and returns each match's id, title, preview and last change. Without a query, returns the most recent notes. Read one with read_note.",
                inputSchema: MCPTool.schema(["query": MCPTool.string("Words to find; empty for the most recent notes.", maxLength: 200),
                                             "limit": MCPTool.integer("How many notes to return.", minimum: 1, maximum: 25)]),
                readOnly: true, idempotent: true) { [notes] arguments in
            let query = arguments["query"]?.string?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard query.count <= 200 else { return .failure("Keep the query under 200 characters.") }
            let limit = min(max(arguments["limit"]?.int ?? 10, 1), 25)
            let found: [Note] = await withCheckedContinuation { continuation in
                DispatchQueue.main.async {
                    let quick = notes.search(query, limit: limit)
                    if notes.searchFiles(query, limit: limit, completion: { continuation.resume(returning: $0) }) == nil {
                        continuation.resume(returning: quick)
                    }
                }
            }
            return .data(.object(["notes": .array(found.map(Self.describe))]))
        }
    }

    private var readNote: MCPTool {
        MCPTool(name: "read_note", title: "Read a note",
                description: "Returns a Volant note's Markdown by the id search_notes gave. Long notes come in parts of up to 100,000 characters; pass the returned nextOffset to read on.",
                inputSchema: MCPTool.schema(["id": MCPTool.string("The note's id from search_notes."),
                                             "offset": MCPTool.integer("Characters to skip, for long notes.", minimum: 0, maximum: 100_000_000)], required: ["id"]),
                readOnly: true, idempotent: true) { [notes] arguments in
            guard let id = arguments["id"]?.string else { return .failure("Give the note's id from search_notes.") }
            let offset = max(arguments["offset"]?.int ?? 0, 0)
            let found: (Note, String)? = await MainActor.run {
                guard let note = notes.notes.first(where: { $0.id == id }), let text = notes.text(of: id) else { return nil }
                return (note, text)
            }
            guard let (note, text) = found else { return .failure("No readable note has that id. Search again with search_notes.") }
            let start = text.index(text.startIndex, offsetBy: min(offset, text.count))
            let end = text.index(start, offsetBy: Self.maximumText, limitedBy: text.endIndex) ?? text.endIndex
            var fields: [String: MCPValue] = ["id": .string(id), "title": .string(note.title), "text": .string(String(text[start..<end])),
                                              "length": .int(text.count)]
            if end < text.endIndex { fields["nextOffset"] = .int(text.distance(from: text.startIndex, to: end)) }
            return .data(.object(fields))
        }
    }

    private var listSnippets: MCPTool {
        MCPTool(name: "list_snippets", title: "List snippets",
                description: "Lists the owner's Volant snippets: name, keyword and text. Placeholders such as {date} and {clipboard} are shown as written, not expanded.",
                inputSchema: MCPTool.noArguments, readOnly: true, idempotent: true) { [configURL] _ in
            guard let config = Self.load(configURL) else { return .failure("Volant's configuration couldn't be read.") }
            return .data(.object(["snippets": .array(config.snippets.map {
                .object(["name": .string($0.name), "keyword": .string($0.keyword), "text": .string(String($0.body.prefix(10_000)))])
            })]))
        }
    }

    private var listQuicklinks: MCPTool {
        MCPTool(name: "list_quicklinks", title: "List quicklinks",
                description: "Lists the owner's Volant quicklinks: name and URL. A {query} in a URL is replaced by what the owner types after the name.",
                inputSchema: MCPTool.noArguments, readOnly: true, idempotent: true) { [configURL] _ in
            guard let config = Self.load(configURL) else { return .failure("Volant's configuration couldn't be read.") }
            return .data(.object(["quicklinks": .array(config.quicklinks.map { .object(["name": .string($0.name), "url": .string($0.url)]) })]))
        }
    }

    private var breakStatusTool: MCPTool {
        MCPTool(name: "break_status", title: "Breaks and break history",
                description: "Whether Volant's break reminders are on, when the next break is, and the owner's breaks: today's count, skips and minutes, and each of the last seven days.",
                inputSchema: MCPTool.noArguments, readOnly: true, idempotent: true) { [breakStatus, breakHistoryURL] _ in
            let status = await MainActor.run { breakStatus() }
            let summary = BreakHistory.summary(BreakHistoryStore.load(url: breakHistoryURL), now: Date())
            func day(_ day: BreakHistory.Day) -> MCPValue {
                .object(["day": .string(day.day), "breaks": .int(day.breaks), "skipped": .int(day.skipped), "minutes": .int(Int((day.seconds / 60).rounded()))])
            }
            return .data(.object(["enabled": .bool(status.enabled), "status": .string(status.status), "today": day(summary.today),
                                  "lastSevenDays": .array(summary.week.map(day))]))
        }
    }

    private var focusStatusTool: MCPTool {
        MCPTool(name: "focus_status", title: "Focus session",
                description: "Whether a Volant Focus session is running, its goal, whether it's paused, and the time left (or how long it has run without a limit).",
                inputSchema: MCPTool.noArguments, readOnly: true, idempotent: true) { [focusStatus] _ in
            guard let session = await MainActor.run(body: { focusStatus() }) else { return .data(.object(["active": .bool(false)])) }
            return .data(.object(["active": .bool(true), "goal": .string(session.goal), "paused": .bool(session.paused), "time": .string(session.time)]))
        }
    }

    private var createNote: MCPTool {
        MCPTool(name: "create_note", title: "Create a note",
                description: "Creates a Volant note from Markdown; a first line starting with # becomes its title. Returns the new note's id.",
                inputSchema: MCPTool.schema(["text": MCPTool.string("The note's Markdown.", maxLength: Self.maximumText)], required: ["text"]),
                readOnly: false) { [notes] arguments in
            guard let text = arguments["text"]?.string, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, text.count <= Self.maximumText else {
                return .failure("Give the note's text, up to 100,000 characters.")
            }
            let note = await MainActor.run { notes.create(initialText: text) }
            return .data(.object(["id": .string(note.id), "title": .string(note.title)]))
        }
    }

    private var appendToNote: MCPTool {
        MCPTool(name: "append_to_note", title: "Add to a note",
                description: "Adds Markdown to the end of an existing Volant note, on a new line, by the id search_notes gave.",
                inputSchema: MCPTool.schema(["id": MCPTool.string("The note's id from search_notes."),
                                             "text": MCPTool.string("The Markdown to add.", maxLength: Self.maximumText)], required: ["id", "text"]),
                readOnly: false) { [notes] arguments in
            guard let id = arguments["id"]?.string, let text = arguments["text"]?.string, !text.isEmpty, text.count <= Self.maximumText else {
                return .failure("Give the note's id and the text to add, up to 100,000 characters.")
            }
            let updated: Bool = await MainActor.run {
                guard let existing = notes.text(of: id) else { return false }
                let separator = existing.isEmpty || existing.hasSuffix("\n") ? "" : "\n"
                notes.update(id, text: existing + separator + text)
                return notes.text(of: id) == existing + separator + text
            }
            return updated ? .data(.object(["id": .string(id)])) : .failure("No editable note has that id. Search again with search_notes.")
        }
    }

    private var addSnippet: MCPTool {
        MCPTool(name: "add_snippet", title: "Add a snippet",
                description: "Adds a Volant snippet the owner can paste by name or keyword. Placeholders: {date}, {isodate}, {time}, {datetime}, {clipboard}, {uuid}. Names must be new; a keyword must be one word not used by another snippet, quicklink, alias or built-in command.",
                inputSchema: MCPTool.schema(["name": MCPTool.string("The snippet's name.", maxLength: 100),
                                             "keyword": MCPTool.string("An optional one-word keyword.", maxLength: 40),
                                             "text": MCPTool.string("The snippet's text.", maxLength: 10_000)], required: ["name", "text"]),
                readOnly: false) { [configURL, configChanged] arguments in
            guard let name = arguments["name"]?.string, let text = arguments["text"]?.string else { return .failure("Give the snippet's name and text.") }
            let snippet = Snippet(name: name, keyword: arguments["keyword"]?.string ?? "", body: text)
            return await Self.append(configURL, configChanged) { try LauncherEntries.appendSnippet(snippet, expected: $0, at: configURL) }
        }
    }

    private var addQuicklink: MCPTool {
        MCPTool(name: "add_quicklink", title: "Add a quicklink",
                description: "Adds a Volant quicklink the owner opens by typing its name. URLs may use https, http, mailto or a Shortcuts run link; {query} is replaced by what the owner types after the name. The name must be new and not a built-in command.",
                inputSchema: MCPTool.schema(["name": MCPTool.string("The quicklink's name, typed in the launcher.", maxLength: 100),
                                             "url": MCPTool.string("The URL, optionally with {query}.", maxLength: 2_000)], required: ["name", "url"]),
                readOnly: false) { [configURL, configChanged] arguments in
            guard let name = arguments["name"]?.string, let url = arguments["url"]?.string else { return .failure("Give the quicklink's name and URL.") }
            return await Self.append(configURL, configChanged) { try LauncherEntries.appendQuicklink(Quicklink(name: name, url: url), expected: $0, at: configURL) }
        }
    }

    /// Appends through `LauncherEntries` against the configuration as it is on disk now, then reloads.
    /// Validation and conflict messages go back to the model so it can correct the request.
    private static func append(_ url: URL, _ changed: @escaping @MainActor () -> Void,
                               _ write: (LauncherEntries.Snapshot) throws -> Preferences) async -> MCPToolResult {
        guard let config = load(url) else { return .failure("Volant's configuration couldn't be read.") }
        do {
            _ = try write(LauncherEntries.Snapshot(config))
        } catch let failure as LauncherEntries.Failure {
            return .failure(failure.message)
        } catch {
            return .failure("Volant couldn't save its configuration.")
        }
        await MainActor.run { changed() }
        return .data(.object(["saved": .bool(true)]))
    }

    private static func load(_ url: URL) -> Preferences? {
        (try? Data(contentsOf: url)).flatMap { try? JSONDecoder().decode(Preferences.self, from: $0) }
    }

    private static func describe(_ note: Note) -> MCPValue {
        .object(["id": .string(note.id), "title": .string(note.title), "preview": .string(note.preview),
                 "modified": .string(note.modified.formatted(.iso8601))])
    }
}
