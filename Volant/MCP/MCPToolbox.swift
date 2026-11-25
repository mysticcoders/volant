import Foundation
import VolantCore

/// The tools Volant offers AI apps, built from the app's own stores so each tool runs the same code
/// the launcher and Settings use: notes through `NotesStore` and its save and retry rules, snippets and
/// quicklinks through `LauncherEntries`' validated, stale-checked patches. Write tools are listed only
/// while their switch is on. Arguments and results are never logged.
struct MCPToolbox {
    /// The longest text one call returns or accepts.
    static let maximumText = 100_000
    /// Resources per `resources/list` page.
    static let resourcePage = 50

    /// What an AI app can ask Focus and Breaks to do.
    enum FocusControl: Equatable { case start(goal: String?, minutes: Int?), pause, resume, end }
    enum BreakControl: Equatable { case takeNow, end, skip, pauseHour, resume }

    let notes: NotesStore
    let configURL: URL
    let breakHistoryURL: URL
    /// The Breaks and Focus status lines the launcher shows, read on the main queue.
    var breakStatus: @MainActor () -> (enabled: Bool, status: String) = { (false, "") }
    var focusStatus: @MainActor () -> (goal: String, paused: Bool, time: String)? = { nil }
    /// Reloads the configuration after a snippet or quicklink was added.
    var configChanged: @MainActor () -> Void = {}
    /// Runs a Focus or Breaks control through its controller; returns why it couldn't, or nil when done.
    var focusControl: @MainActor (FocusControl) -> String? = { _ in "Focus isn't available." }
    var breakControl: @MainActor (BreakControl) -> String? = { _ in "Breaks aren't available." }
    /// Asks the owner in Volant before a sensitive tool runs; true when allowed.
    var approve: (_ client: String, _ tool: String, _ summary: String) async -> Bool = { _, _, _ in false }
    /// The sensitive tools' sources, the same code the launcher uses; nil means unavailable.
    var clipboard: @MainActor (_ query: String, _ limit: Int) -> [(text: String, copiedAt: Date)]? = { _, _ in nil }
    var files: (_ term: String) async -> [FileEntry]? = { _ in nil }
    var currency: (_ query: String) async -> CalculationAnswer? = { _ in nil }
    var weather: (_ place: String) async -> (report: WeatherReport?, message: String?) = { _ in (nil, nil) }

    func tools(_ preferences: MCPPreferences, client: String = "") -> [MCPTool] {
        var tools = [calculate, searchNotes, readNote, listSnippets, listQuicklinks, breakStatusTool, focusStatusTool]
        if preferences.writesNotes { tools += [createNote, appendToNote] }
        if preferences.writesSnippets { tools.append(addSnippet) }
        if preferences.writesQuicklinks { tools.append(addQuicklink) }
        if preferences.controlsFocus {
            tools += [startFocus,
                      focusTool("pause_focus", "Pause Focus", "Pauses the running Volant Focus session; blocked apps and sites are allowed until it resumes.", .pause),
                      focusTool("resume_focus", "Resume Focus", "Resumes a paused Volant Focus session.", .resume),
                      focusTool("end_focus", "End Focus", "Ends the running Volant Focus session early.", .end)]
        }
        if preferences.controlsBreaks {
            tools += [breakTool("take_break", "Take a break now", "Starts a Volant break now, for the owner's break length.", .takeNow),
                      breakTool("end_break", "End the break", "Ends the running Volant break early.", .end),
                      breakTool("skip_break", "Skip the next break", "Skips the next or running Volant break; the stretch of work starts over.", .skip),
                      breakTool("pause_breaks", "Pause breaks for an hour", "Holds Volant's break reminders for an hour.", .pauseHour),
                      breakTool("resume_breaks", "Resume breaks", "Ends a pause of Volant's break reminders.", .resume)]
        }
        if preferences.sharesClipboard { tools.append(searchClipboard(client)) }
        if preferences.searchesFiles { tools.append(searchFiles(client)) }
        if preferences.convertsCurrency { tools.append(convertCurrency(client)) }
        if preferences.checksWeather { tools.append(checkWeather(client)) }
        return tools
    }

    /// The text every sensitive tool returns when the owner says no or doesn't answer.
    static let denied = "The owner didn't allow this in Volant. Don't retry unless they ask you to."

    private func searchClipboard(_ client: String) -> MCPTool {
        MCPTool(name: "search_clipboard", title: "Search clipboard history",
                description: "Searches the owner's Volant clipboard history for text containing the query and returns matching entries, newest first, with when each was copied. Volant asks the owner before every search unless they chose Always Allow; items Volant doesn't keep, such as passwords from password managers, are never there.",
                inputSchema: MCPTool.schema(["query": MCPTool.string("Text to find.", maxLength: 200),
                                             "limit": MCPTool.integer("How many entries to return.", minimum: 1, maximum: 20)], required: ["query"]),
                readOnly: true, idempotent: true) { [approve, clipboard] arguments in
            guard let query = arguments["query"]?.string?.trimmingCharacters(in: .whitespacesAndNewlines), (1...200).contains(query.count) else {
                return .failure("Give a query of 1 to 200 characters.")
            }
            let limit = min(max(arguments["limit"]?.int ?? 10, 1), 20)
            guard await approve(client, "search_clipboard", String(localized: "Search your clipboard history for “\(query, format: .verbatim)”", comment: "Connected Apps approval prompt: what the AI app asks to do; the value is its search text")) else {
                return .failure(Self.denied)
            }
            guard let found = await MainActor.run(body: { clipboard(query, limit) }) else { return .failure("Volant's clipboard history isn't available right now.") }
            return .data(.object(["entries": .array(found.map { entry in
                var fields: [String: MCPValue] = ["text": .string(String(entry.text.prefix(2_000))), "copied": .string(entry.copiedAt.formatted(.iso8601))]
                if entry.text.count > 2_000 { fields["truncated"] = .bool(true) }
                return .object(fields)
            })]))
        }
    }

    private func searchFiles(_ client: String) -> MCPTool {
        MCPTool(name: "search_files", title: "Search file names",
                description: "Finds files in the owner's home folder whose names contain the term, newest first, and returns up to 8 names and paths. It never reads file contents. Volant asks the owner before every search unless they chose Always Allow.",
                inputSchema: MCPTool.schema(["term": MCPTool.string("Part of a file name, 3 to 200 characters.", maxLength: 200)], required: ["term"]),
                readOnly: true, idempotent: true) { [approve, files] arguments in
            guard let raw = arguments["term"]?.string, let term = HomeFileSearch.term(raw) else {
                return .failure("Give part of a file name, 3 to 200 characters.")
            }
            guard await approve(client, "search_files", String(localized: "Search file names in your home folder for “\(term, format: .verbatim)”", comment: "Connected Apps approval prompt: what the AI app asks to do; the value is its search term")) else {
                return .failure(Self.denied)
            }
            guard let found = await files(term) else { return .failure("Volant's file search isn't available right now.") }
            return .data(.object(["files": .array(found.map { .object(["name": .string($0.name), "path": .string($0.url.path)]) })]))
        }
    }

    private func convertCurrency(_ client: String) -> MCPTool {
        MCPTool(name: "convert_currency", title: "Convert currency",
                description: "Volant's currency converter: amounts and arithmetic in currencies and crypto, such as `120 USD in EUR` or `0.5 BTC to USD`. Rates come from the European Central Bank, with ExchangeRate-API for currencies the ECB doesn't publish and CoinGecko for crypto, fetched by Volant's rates helper when they're out of date. Volant asks the owner before every conversion unless they chose Always Allow.",
                inputSchema: MCPTool.schema(["query": MCPTool.string("The conversion, as you would type it in Volant's launcher.", maxLength: 120)], required: ["query"]),
                readOnly: true) { [approve, currency] arguments in
            guard let query = arguments["query"]?.string?.trimmingCharacters(in: .whitespacesAndNewlines), (1...120).contains(query.utf8.count) else {
                return .failure("Give a conversion of 1 to 120 characters, such as `120 USD in EUR`.")
            }
            guard await approve(client, "convert_currency", String(localized: "Convert “\(query, format: .verbatim)”, fetching exchange rates if needed", comment: "Connected Apps approval prompt: what the AI app asks to do; the value is its conversion")) else {
                return .failure(Self.denied)
            }
            guard let answer = await currency(query) else {
                return .failure("Volant couldn't convert that. Name the currencies by code, such as `120 USD in EUR`, or try again if rates were still loading.")
            }
            var fields: [String: MCPValue] = ["input": .string(answer.input), "result": .string(answer.result)]
            if let detail = answer.resultDetail { fields["detail"] = .string(detail) }
            return .data(.object(fields))
        }
    }

    private func checkWeather(_ client: String) -> MCPTool {
        MCPTool(name: "get_weather", title: "Check the weather",
                description: "The current conditions and today's forecast for a named place, from Apple Weather through Volant's weather helper. It never uses the owner's location. Temperatures are Celsius. Show the attribution with the forecast. Volant asks the owner before every request unless they chose Always Allow.",
                inputSchema: MCPTool.schema(["place": MCPTool.string("A city or place name.", maxLength: WeatherQuery.maximumPlaceLength)], required: ["place"]),
                readOnly: true) { [approve, weather] arguments in
            guard let place = arguments["place"]?.string?.trimmingCharacters(in: .whitespacesAndNewlines), WeatherQuery.validPlace(place) else {
                return .failure("Give a place name of 1 to \(WeatherQuery.maximumPlaceLength) characters.")
            }
            guard await approve(client, "get_weather", String(localized: "Check the weather in “\(place, format: .verbatim)”", comment: "Connected Apps approval prompt: what the AI app asks to do; the value is the place")) else {
                return .failure(Self.denied)
            }
            let (report, message) = await weather(place)
            guard let report else { return .failure(message ?? "Apple Weather didn't answer. Try again in a moment.") }
            let forecast = report.forecast
            var fields: [String: MCPValue] = ["place": .string(forecast.place), "attribution": .string("Weather data from Apple Weather")]
            if let legal = report.legalURL { fields["legalURL"] = .string(legal) }
            if let condition = forecast.condition { fields["condition"] = .string(condition) }
            if let value = forecast.temperature { fields["temperatureCelsius"] = .double(value) }
            if let value = forecast.high { fields["highCelsius"] = .double(value) }
            if let value = forecast.low { fields["lowCelsius"] = .double(value) }
            return .data(.object(fields))
        }
    }

    /// Notes, snippets and quicklinks as resources: `volant://snippets`, `volant://quicklinks` and
    /// `volant://notes/<id>`. A note is found by its id in the notes list, never by building a path.
    func resources() -> MCPResources {
        let notes = notes, configURL = configURL
        return MCPResources(list: { cursor in
            let offset = cursor.flatMap(Int.init) ?? 0
            let listed: [Note] = await MainActor.run { notes.notes }
            var all: [MCPValue] = [
                .object(["uri": .string("volant://snippets"), "name": .string("snippets"), "title": .string("Snippets"), "mimeType": .string("application/json")]),
                .object(["uri": .string("volant://quicklinks"), "name": .string("quicklinks"), "title": .string("Quicklinks"), "mimeType": .string("application/json")])
            ]
            all += listed.filter { $0.readError == nil && !$0.downloading }.map { note in
                .object(["uri": .string(Self.noteURI(note.id)), "name": .string(note.id), "title": .string(note.title), "mimeType": .string("text/markdown"),
                         "annotations": .object(["lastModified": .string(note.modified.formatted(.iso8601))])])
            }
            guard offset >= 0, offset <= all.count else { return ([], nil) }
            let end = min(offset + Self.resourcePage, all.count)
            return (Array(all[offset..<end]), end < all.count ? String(end) : nil)
        }, read: { uri in
            if uri == "volant://snippets" || uri == "volant://quicklinks" {
                guard let config = Self.load(configURL) else { return nil }
                let value: MCPValue = uri == "volant://snippets"
                    ? .array(config.snippets.map { .object(["name": .string($0.name), "keyword": .string($0.keyword), "text": .string($0.body)]) })
                    : .array(config.quicklinks.map { .object(["name": .string($0.name), "url": .string($0.url)]) })
                return [.object(["uri": .string(uri), "mimeType": .string("application/json"), "text": .string(String(decoding: value.line(), as: UTF8.self))])]
            }
            guard uri.hasPrefix("volant://notes/"), let id = String(uri.dropFirst("volant://notes/".count)).removingPercentEncoding else { return nil }
            let text: String? = await MainActor.run { notes.notes.contains { $0.id == id } ? notes.text(of: id) : nil }
            guard let text else { return nil }
            return [.object(["uri": .string(uri), "mimeType": .string("text/markdown"), "text": .string(String(text.prefix(1_000_000)))])]
        }, templates: [.object(["uriTemplate": .string("volant://notes/{id}"), "name": .string("note"), "title": .string("A Volant note"),
                                "description": .string("A note's Markdown by the id search_notes returns."), "mimeType": .string("text/markdown")])])
    }

    static func noteURI(_ id: String) -> String {
        "volant://notes/" + (id.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed.subtracting(CharacterSet(charactersIn: "/"))) ?? id)
    }

    private var startFocus: MCPTool {
        MCPTool(name: "start_focus", title: "Start Focus",
                description: "Starts a Volant Focus session with the owner's remembered block list, replacing any running one. Optionally sets a goal and a length in minutes; otherwise the remembered ones apply. The owner's saved setup isn't changed.",
                inputSchema: MCPTool.schema(["goal": MCPTool.string("What the session is for.", maxLength: 200),
                                             "minutes": MCPTool.integer("How long, in minutes.", minimum: 1, maximum: FocusSetup.maximumMinutes)]),
                readOnly: false) { [focusControl, focusStatus] arguments in
            let goal = arguments["goal"]?.string?.trimmingCharacters(in: .whitespacesAndNewlines)
            let minutes = arguments["minutes"]?.int
            if let minutes, !(1...FocusSetup.maximumMinutes).contains(minutes) { return .failure("Give a length from 1 to \(FocusSetup.maximumMinutes) minutes.") }
            if let goal, goal.count > 200 { return .failure("Keep the goal under 200 characters.") }
            return await Self.run({ focusControl(.start(goal: goal?.isEmpty == true ? nil : goal, minutes: minutes)) }, then: { Self.describeFocus(focusStatus()) })
        }
    }

    private func focusTool(_ name: String, _ title: String, _ description: String, _ control: FocusControl) -> MCPTool {
        MCPTool(name: name, title: title, description: description, inputSchema: MCPTool.noArguments, readOnly: false) { [focusControl, focusStatus] _ in
            await Self.run({ focusControl(control) }, then: { Self.describeFocus(focusStatus()) })
        }
    }

    private func breakTool(_ name: String, _ title: String, _ description: String, _ control: BreakControl) -> MCPTool {
        MCPTool(name: name, title: title, description: description, inputSchema: MCPTool.noArguments, readOnly: false) { [breakControl, breakStatus] _ in
            await Self.run({ breakControl(control) }, then: {
                let status = breakStatus()
                return .object(["enabled": .bool(status.enabled), "status": .string(status.status)])
            })
        }
    }

    /// Runs a Focus or Breaks control through an owner held weakly, such as the app delegate. Returns
    /// `unavailable` only when the owner is gone; a control that ran returns its own result, so its nil
    /// (done) is never mistaken for a missing owner the way `owner?.control(c) ?? unavailable` would.
    @MainActor static func relay<Owner: AnyObject, Control>(_ owner: Owner?, _ control: Control, unavailable: String,
                                                           _ run: @MainActor (Owner, Control) -> String?) -> String? {
        guard let owner else { return unavailable }
        return run(owner, control)
    }

    /// Runs a control on the main queue and returns the state after it, or why it couldn't run.
    private static func run(_ control: @escaping @MainActor () -> String?, then state: @escaping @MainActor () -> MCPValue) async -> MCPToolResult {
        await MainActor.run {
            if let problem = control() { return .failure(problem) }
            return .data(state())
        }
    }

    private static func describeFocus(_ session: (goal: String, paused: Bool, time: String)?) -> MCPValue {
        guard let session else { return .object(["active": .bool(false)]) }
        return .object(["active": .bool(true), "goal": .string(session.goal), "paused": .bool(session.paused), "time": .string(session.time)])
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
