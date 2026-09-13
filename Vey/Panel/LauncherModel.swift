import AppKit
import Combine

enum NoteAction {
    case open(String)
    case create(String)
}

enum ResultRow: Identifiable, Hashable {
    case snippet(Snippet)
    case emoji(EmojiEntry)
    case quicklink(Quicklink, query: String)
    case extensionRun(InstalledExtension, input: String)
    case extensionResult(String)
    case note(Note)
    case newNote(String)
    case calculation(String)
    case unit(String)
    case app(AppEntry)
    case file(FileEntry)
    case contact(ContactEntry)
    case event(EventEntry)
    case clip(ClipEntry)

    var id: String {
        switch self {
        case .calculation(let s): return "calc:\(s)"
        case .unit(let s): return "unit:\(s)"
        case .app(let a): return "app:\(a.id)"
        case .file(let f): return "file:\(f.id)"
        case .contact(let c): return "contact:\(c.id)"
        case .event(let e): return "event:\(e.id)"
        case .clip(let c): return "clip:\(c.id)"
        case .note(let n): return "note:\(n.id)"
        case .newNote(let t): return "newnote:\(t)"
        case .extensionRun(let e, let i): return "ext:\(e.id):\(i)"
        case .extensionResult(let s): return "extresult:\(s)"
        case .snippet(let s): return "snip:\(s.keyword)"
        case .emoji(let e): return "emoji:\(e.symbol)"
        case .quicklink(let q, let t): return "ql:\(q.name):\(t)"
        }
    }

    /// Right-aligned kind label, as in Raycast's "Application" / "Command" column.
    var kind: String {
        switch self {
        case .calculation: return "Calculation"
        case .unit: return "Conversion"
        case .app: return "Application"
        case .file: return "File"
        case .contact: return "Contact"
        case .event: return "Event"
        case .clip: return "Clipboard"
        case .note, .newNote: return "Note"
        case .extensionRun: return "Extension"
        case .extensionResult: return "Result"
        case .snippet: return "Snippet"
        case .emoji: return "Emoji"
        case .quicklink: return "Quicklink"
        }
    }

    /// Footer label for return.
    var primaryAction: String {
        switch self {
        case .calculation, .unit: return "Copy Result"
        case .app: return "Open Application"
        case .file: return "Open File"
        case .contact(let c): return c.email != nil ? "Copy Email" : "Copy Phone"
        case .event(let e): return e.joinURL != nil ? "Join Meeting" : "Open Calendar"
        case .clip: return "Copy to Clipboard"
        case .note: return "Open Note"
        case .newNote: return "Create Note"
        case .extensionRun: return "Run Extension"
        case .extensionResult: return "Copy Result"
        case .snippet: return "Copy Snippet"
        case .emoji: return "Copy Emoji"
        case .quicklink: return "Open Link"
        }
    }

    /// Footer label for command-return, when a secondary action exists.
    var secondaryAction: String? {
        switch self {
        case .file: return "Reveal in Finder"
        case .app: return "Reveal in Finder"
        case .contact(let c): return c.email != nil && c.phone != nil ? "Copy Phone" : nil
        default: return nil
        }
    }
}

struct ResultSection: Identifiable {
    let title: String
    let rows: [ResultRow]
    var id: String { title }
}

/// Routes a query. Prefixes force one source: `/` files, `@` contacts, `cal` or `today` agenda, `clip` history.
/// Otherwise results merge: math and units first, then apps, contacts, and files once the query is long enough.
final class LauncherModel: ObservableObject {
    @Published var query: String = "" { didSet { refresh() } }
    @Published var sections: [ResultSection] = []
    @Published var selection: Int = 0
    @Published var notice: String? = nil
    var dismiss: () -> Void = {}

    var rows: [ResultRow] { sections.flatMap(\.rows) }
    var selectedRow: ResultRow? { rows.indices.contains(selection) ? rows[selection] : nil }

    private let index: AppIndex
    private let clipboard: ClipboardStore
    private let notes: NotesStore
    private let onNote: (NoteAction) -> Void
    let extensions = ExtensionManager()
    var config: Preferences
    private let files = FileSearch()
    private let contacts = ContactSearch()
    private let agenda = CalendarAgenda()
    private var generation = 0
    private var immediate: [ResultSection] = []
    private var contactRows: [ResultRow] = []
    private var fileRows: [ResultRow] = []

    init(index: AppIndex, clipboard: ClipboardStore, notes: NotesStore, config: Preferences, onNote: @escaping (NoteAction) -> Void) {
        self.index = index
        self.clipboard = clipboard
        self.notes = notes
        self.config = config
        self.onNote = onNote
    }

    func reset() {
        files.cancel()
        query = ""
        selection = 0
        showSuggestions()
    }

    private func showSuggestions() {
        let apps = index.suggestions().map { ResultRow.app($0) }
        sections = apps.isEmpty ? [] : [ResultSection(title: "Suggestions", rows: apps)]
    }

    private func refresh() {
        selection = 0
        generation += 1
        let gen = generation
        immediate = []; contactRows = []; fileRows = []
        notice = nil
        files.cancel()
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { showSuggestions(); return }

        if q.hasPrefix("/") {
            let term = String(q.dropFirst()).trimmingCharacters(in: .whitespaces)
            sections = []
            files.search(term) { [weak self] hits in self?.deliver(gen) { $0.fileRows = hits.map { .file($0) } } }
            return
        }
        if q.hasPrefix("@") {
            let term = String(q.dropFirst()).trimmingCharacters(in: .whitespaces)
            sections = []
            contacts.search(term, askIfNeeded: true) { [weak self] hits in self?.deliver(gen) { $0.contactRows = hits.map { .contact($0) } } }
            return
        }
        if q.lowercased() == "cal" || q.lowercased() == "today" || q.lowercased().hasPrefix("cal ") {
            sections = []
            agenda.upcoming { [weak self] outcome in
                self?.deliver(gen) { model in
                    switch outcome {
                    case .denied:
                        model.notice = "Calendar access is off. Enable it in System Settings, Privacy & Security, Calendars."
                        model.immediate = []
                    case .events(let events):
                        model.notice = events.isEmpty ? "Nothing scheduled through tomorrow." : nil
                        let today = events.filter { Calendar.current.isDateInToday($0.start) }
                        let tomorrow = events.filter { !Calendar.current.isDateInToday($0.start) }
                        model.immediate = []
                        if !today.isEmpty { model.immediate.append(ResultSection(title: "Today", rows: today.map { .event($0) })) }
                        if !tomorrow.isEmpty { model.immediate.append(ResultSection(title: "Tomorrow", rows: tomorrow.map { .event($0) })) }
                    }
                }
            }
            return
        }
        if q.hasPrefix(":") {
            let rows = EmojiIndex.search(String(q.dropFirst())).map { ResultRow.emoji($0) }
            sections = rows.isEmpty ? [] : [ResultSection(title: "Emoji", rows: rows)]
            return
        }
        if q.lowercased() == "snip" || q.lowercased().hasPrefix("snip ") {
            let rows = SnippetExpander.search(config.snippets, q.dropFirst(4).trimmingCharacters(in: .whitespaces)).map { ResultRow.snippet($0) }
            notice = rows.isEmpty ? "No snippets. Add them under \"snippets\" in config.json." : nil
            sections = rows.isEmpty ? [] : [ResultSection(title: "Snippets", rows: rows)]
            return
        }
        if q.lowercased() == "ext" || q.lowercased().hasPrefix("ext ") {
            let rest = q.dropFirst(3).trimmingCharacters(in: .whitespaces)
            let parts = rest.split(separator: " ", maxSplits: 1).map(String.init)
            let name = parts.first ?? ""
            let input = parts.count > 1 ? parts[1] : ""
            extensions.reload()
            let rows = extensions.search(name).map { ResultRow.extensionRun($0, input: input) }
            notice = rows.isEmpty ? "No extensions installed. Folders go in Application Support/Vey/Extensions." : nil
            sections = rows.isEmpty ? [] : [ResultSection(title: "Extensions", rows: rows)]
            return
        }
        if q.lowercased() == "note" || q.lowercased().hasPrefix("note ") {
            let term = q.dropFirst(4).trimmingCharacters(in: .whitespaces)
            notes.reload()
            var rows = notes.search(term).map { ResultRow.note($0) }
            if !term.isEmpty { rows.append(.newNote(term)) }
            sections = rows.isEmpty ? [] : [ResultSection(title: term.isEmpty ? "Recent Notes" : "Notes", rows: rows)]
            return
        }
        if q.lowercased() == "clip" || q.lowercased().hasPrefix("clip ") {
            let term = q.dropFirst(4).trimmingCharacters(in: .whitespaces)
            let clips = clipboard.recent(limit: 12, matching: term).map { ResultRow.clip($0) }
            sections = clips.isEmpty ? [] : [ResultSection(title: "Clipboard History", rows: clips)]
            return
        }

        var answers: [ResultRow] = []
        if let value = Calculator.evaluate(q) { answers.append(.calculation(Calculator.format(value))) }
        if let conv = UnitConverter.convert(q) { answers.append(.unit(UnitConverter.format(conv))) }
        immediate = []
        let words = q.split(separator: " ", maxSplits: 1).map(String.init)
        let head = words.first?.lowercased() ?? ""
        let tail = words.count > 1 ? words[1] : ""
        if let target = config.aliases[head], words.count == 1, let app = index.search(target, limit: 1).first {
            immediate.append(ResultSection(title: "Alias", rows: [.app(app)]))
        }
        if !answers.isEmpty { immediate.append(ResultSection(title: "Answer", rows: answers)) }
        let snips = config.snippets.filter { $0.keyword.lowercased() == q.lowercased() }.map { ResultRow.snippet($0) }
        if !snips.isEmpty { immediate.append(ResultSection(title: "Snippets", rows: snips)) }
        let links = QuicklinkResolver.search(config.quicklinks, head).map { ResultRow.quicklink($0, query: tail) }
        if !links.isEmpty { immediate.append(ResultSection(title: "Quicklinks", rows: links)) }
        let aliased = Set(immediate.flatMap(\.rows).map(\.id))
        let apps = index.search(q, limit: 6).map { ResultRow.app($0) }.filter { !aliased.contains($0.id) }
        if !apps.isEmpty { immediate.append(ResultSection(title: "Applications", rows: apps)) }
        compose()

        let letters = q.filter(\.isLetter).count
        if letters >= 2 && q.count <= 40 {
            contacts.search(q, askIfNeeded: false) { [weak self] hits in
                let needle = q.lowercased()
                let tight = hits.filter { c in c.name.lowercased().split(separator: " ").contains { $0.hasPrefix(needle) } || c.name.lowercased().hasPrefix(needle) }
                self?.deliver(gen) { $0.contactRows = tight.prefix(3).map { .contact($0) } }
            }
        }
        if q.count >= 3 {
            files.search(q) { [weak self] hits in self?.deliver(gen) { $0.fileRows = hits.prefix(5).map { .file($0) } } }
        }
    }

    private func deliver(_ gen: Int, _ apply: (LauncherModel) -> Void) {
        guard gen == generation else { return }
        apply(self)
        compose()
    }

    /// Keeps the selected row by identity when async sections arrive above it.
    private func compose() {
        let selectedID = selectedRow?.id
        var out = immediate
        if !contactRows.isEmpty { out.append(ResultSection(title: "Contacts", rows: contactRows)) }
        if !fileRows.isEmpty { out.append(ResultSection(title: "Files", rows: fileRows)) }
        sections = out
        if let selectedID, let i = rows.firstIndex(where: { $0.id == selectedID }) { selection = i }
        else if selection >= rows.count { selection = 0 }
    }

    func moveSelection(_ delta: Int) {
        let count = rows.count
        guard count > 0 else { return }
        selection = (selection + delta + count) % count
    }

    private func copy(_ text: String) {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(text, forType: .string)
    }

    func activateSelection() {
        guard let row = selectedRow else { return }
        switch row {
        case .calculation(let text): copy(text)
        case .unit(let text): copy(text.components(separatedBy: " = ").last ?? text)
        case .clip(let clip):
            if clip.kind == .image, let data = clip.imageData {
                let pb = NSPasteboard.general; pb.clearContents(); pb.setData(data, forType: .png)
            } else { copy(clip.text) }
        case .app(let app): index.launch(app)
        case .file(let file): FileSearch.open(file)
        case .contact(let contact): if let value = contact.copyValue { copy(value) }
        case .event(let event): CalendarAgenda.open(event)
        case .note(let note): onNote(.open(note.id))
        case .newNote(let text): onNote(.create(text + "\n"))
        case .extensionRun(let ext, let input):
            let gen = generation
            extensions.run(ext, input: input) { [weak self] result in
                guard let self, gen == self.generation else { return }
                switch result {
                case .success(let output):
                    self.sections = [ResultSection(title: ext.name, rows: [.extensionResult(output)])]
                case .failure(let error):
                    self.notice = "Extension failed: \(error.localizedDescription)"
                    self.sections = []
                }
            }
            return
        case .extensionResult(let text): copy(text)
        case .snippet(let snippet): copy(SnippetExpander.expand(snippet.body))
        case .emoji(let e): copy(e.symbol)
        case .quicklink(let link, let query):
            if QuicklinkResolver.needsQuery(link) && query.isEmpty { self.query = link.name + " "; return }
            if let url = QuicklinkResolver.url(for: link, query: query) { QuicklinkResolver.open(url) }
        }
        dismiss()
    }

    func activateSecondary() {
        guard let row = selectedRow else { return }
        switch row {
        case .file(let file): FileSearch.reveal(file)
        case .app(let app): NSWorkspace.shared.activateFileViewerSelecting([app.url])
        case .contact(let contact): if let phone = contact.phone { copy(phone) }
        default: activateSelection(); return
        }
        dismiss()
    }
}
