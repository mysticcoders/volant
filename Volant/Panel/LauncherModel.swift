import AppKit
import Combine
import OSLog

enum LauncherAction {
    case settings
    case reloadConfig
    case editApp(AppEntry)
    case agents
    case open(String)
    case create(String)
}

enum ResultRow: Identifiable, Hashable {
    case core(CoreCommand)
    case caffeinate(CaffeinateCommand)
    case systemSettings(SystemSettingsDestination)
    case settings
    case reloadConfig
    case connectivity(ConnectivityItem)
    case audioRoute(AudioRoute)
    case volume(VolumeCommand, detail: String)
    case agents
    case agentSession(AgentSession)
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
        case .core(let command): return "core:" + command.rawValue
        case .caffeinate(let command): return "caffeinate:" + command.id
        case .agentSession(let session): return "agent:" + session.id
        case .connectivity(let item): return item.id
        case .audioRoute(let route): return "audio:" + route.id
        case .volume(let command, _): return "volume:" + command.id
        case .systemSettings(let pane): return "system-settings:" + pane.id
        case .settings: return "command:settings"
        case .reloadConfig: return "command:reload"
        case .agents: return "command:agents"
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
        case .snippet(let s): return "snip:\(s.name.utf8.count):\(s.name)\(s.keyword.utf8.count):\(s.keyword)\(s.body)"
        case .emoji(let e): return "emoji:\(e.symbol)"
        case .quicklink(let q, let t): return "ql:\(q.name):\(t)"
        }
    }

    /// Right-aligned kind label, as in Raycast's "Application" / "Command" column.
    var kind: String {
        switch self {
        case .core, .caffeinate: return "Command"
        case .agentSession(let session): return session.status
        case .connectivity: return "Connectivity"
        case .audioRoute(let route): return route.current ? "Current" : "Device"
        case .volume: return "System"
        case .systemSettings: return "System Settings"
        case .settings, .reloadConfig: return "Command"
        case .agents: return "Command"
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

    var isCoreCommand: Bool {
        switch self {
        case .core, .caffeinate, .settings, .reloadConfig, .agents, .volume, .audioRoute, .connectivity, .systemSettings: return true
        default: return false
        }
    }

    /// Footer label for return.
    var primaryAction: String {
        switch self {
        case .core: return "Open Command"
        case .caffeinate(let command): return command.stop ? "Stop" : "Start"
        case .agentSession: return "Focus in Herdr"
        case .connectivity(let item):
            if case .wifi(let network) = item { return network.current ? "Connected" : "Join Network" }
            if case .refresh = item { return "Refresh" }
            return "Open Settings"
        case .audioRoute(let route): return route.current ? "Keep Current Device" : "Use as " + route.direction.rawValue.capitalized
        case .volume: return "Apply"
        case .settings, .systemSettings: return "Open Settings"
        case .reloadConfig: return "Reload Configuration"
        case .agents: return "Open Agents"
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

struct ResultSection: Identifiable, Equatable {
    let title: String
    let rows: [ResultRow]
    var id: String { title }
}

/// Routes a query. Prefixes force one source: `/` files, `@` contacts, `cal` or `today` agenda, `clip` history.
/// Otherwise results merge: math and units first, then apps, contacts, and files once the query is long enough.
final class LauncherModel: ObservableObject {
    @Published var query: String = "" { didSet { if oldValue != query { refresh() } } }
    private var flattenedRows: [ResultRow] = []
    @Published private var displayedSections: [ResultSection] = []
    var sections: [ResultSection] {
        get { displayedSections }
        set {
            assert(Thread.isMainThread, "Launcher results must update on the main thread")
            var seen = Set<String>()
            var normalized: [ResultSection] = []
            var duplicates = 0
            for section in newValue {
                let unique = section.rows.filter { row in
                    if seen.insert(row.id).inserted { return true }
                    duplicates += 1
                    return false
                }
                guard !unique.isEmpty else { continue }
                if let index = normalized.firstIndex(where: { $0.id == section.id }) {
                    normalized[index] = ResultSection(title: section.title, rows: normalized[index].rows + unique)
                } else { normalized.append(ResultSection(title: section.title, rows: unique)) }
            }
            if duplicates > 0 { Logger(subsystem: "com.mysticcoders.volant", category: "Launcher").warning("Duplicate result identities ignored: \(duplicates)") }
            guard normalized != displayedSections else { return }
            flattenedRows = normalized.flatMap(\.rows)
            displayedSections = normalized
        }
    }
    @Published var searchFocusRequest = UUID()
    @Published var selection: Int = 0
    @Published var actionFeedback: String?
    let dictionary = DictionaryModel()
    var showingDictionary: Bool { DictionaryQuery.term(query) != nil }
    let translation = TranslationModel()
    var showingTranslation: Bool { ["translate", "translation", "translator"].contains(query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()) }
    let caffeinate: CaffeinateService
    private var caffeinateSubscription: AnyCancellable?
    var showingEmoji: Bool { query.trimmingCharacters(in: .whitespaces).hasPrefix(":") }
    var emojiSearch: (String) -> [EmojiEntry] = { EmojiIndex.search($0, limit: Int.max) }
    var searchText: String {
        get { showingEmoji ? String(query.dropFirst()) : query }
        set { query = showingEmoji ? ":" + newValue : newValue }
    }
    static let emojiColumns = 10
    var volumeControl = VolumeControl()
    var audioRouting: AudioRouting = CoreAudioRouting()
    lazy var connectivity: ConnectivityAccess = ConnectivityService()
    @Published var wifiJoin: WiFiChoice?
    @Published var connectivityBusy = false
    @Published var notice: String? = nil
    var dismiss: () -> Void = {}
    let agents = AgentsModel()
    let acp = ACPModel()
    var showingACP: Bool { query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == "acp" }
    @Published var promotedHarness: String?
    var isPresented = false
    private var agentSubscription: AnyCancellable?
    private var indexSubscription: AnyCancellable?
    var showingAgents: Bool {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        return q == "agents" || q == "herdr" || q.hasPrefix("agents ") || q.hasPrefix("herdr ")
    }
    var promotedTitle: String { Preferences.harnessOptions.first { $0.id == promotedHarness }?.title ?? "Agents" }
    var promotedSessions: [AgentSession] { agents.sessions.filter { promotedHarness == "all" || $0.agent == promotedHarness } }
    func promoteHarness(_ id: String?) {
        do {
            try Preferences.updatePromotedHarness(id)
            config.promotedHarness = id
            if id != nil && isPresented && !agents.connected { agents.connect() }
        } catch { notice = "Couldn’t save pinned harness: " + error.localizedDescription }
    }
    func resumeAgentsIfNeeded() {
        if promotedHarness != nil && !agents.connected { agents.connect() }
    }
    func showPromotedAgents() {
        query = "agents" + (promotedHarness == "all" ? "" : " " + (promotedHarness ?? ""))
    }
    private func refreshAgentResults() {
        guard showingAgents else { return }
        let selectedID = selectedRow?.id
        let parts = query.trimmingCharacters(in: .whitespaces).split(separator: " ", maxSplits: 1)
        let term = parts.count > 1 ? String(parts[1]) : ""
        let sessions = agents.sessions.filter {
            term.isEmpty || [$0.project, $0.provider, $0.agent, $0.status, $0.cwd ?? "", $0.terminalTitle ?? ""].joined(separator: " ").localizedCaseInsensitiveContains(term)
        }
        sections = sessions.isEmpty ? [] : [ResultSection(title: "Herdr panes", rows: sessions.map(ResultRow.agentSession))]
        notice = agents.connected ? (agents.busy && agents.sessions.isEmpty ? "Loading Herdr panes…" : (sessions.isEmpty && !agents.sessions.isEmpty ? "No matching panes" : agents.message)) : agents.message
        if let selectedID, let index = rows.firstIndex(where: { $0.id == selectedID }) { selection = index }
        else { selection = min(selection, max(0, rows.count - 1)) }
    }


    var rows: [ResultRow] { flattenedRows }
    var selectedRow: ResultRow? { rows.indices.contains(selection) ? rows[selection] : nil }

    private let index: AppIndex
    private let clipboard: ClipboardStore
    private let notes: NotesStore
    private let onNote: (LauncherAction) -> Void
    let extensions = ExtensionManager()
    let usage: UsageStore
    var config: Preferences { didSet { promotedHarness = config.promotedHarness } }
    var searchesSecondarySources = true
    private let files = FileSearch()
    private let contacts = ContactSearch()
    private let agenda = CalendarAgenda()
    private var searchesAppIndex = false
    private var generation = 0
    private var immediate: [ResultSection] = []
    private var contactRows: [ResultRow] = []
    private var fileRows: [ResultRow] = []

    init(index: AppIndex, clipboard: ClipboardStore, notes: NotesStore, config: Preferences, usage: UsageStore = UsageStore(), caffeinate: CaffeinateService = CaffeinateService(), onNote: @escaping (LauncherAction) -> Void) {
        self.caffeinate = caffeinate
        self.usage = usage
        self.index = index
        self.clipboard = clipboard
        self.notes = notes
        self.config = config
        self.onNote = onNote
        self.promotedHarness = config.promotedHarness
        caffeinateSubscription = caffeinate.$command.dropFirst().sink { [weak self] _ in
            DispatchQueue.main.async {
                guard let self else { return }
                if CaffeinateCommand.matches(self.query) { self.refreshCaffeinateResults() }
            }
        }
        // Spotlight may finish after the first window is already visible.
        // Receive on the next main turn, after @Published has assigned index.apps.
        indexSubscription = index.$apps.dropFirst().receive(on: DispatchQueue.main).sink { [weak self] _ in
            self?.refreshForAppIndex()
        }
        agentSubscription = agents.objectWillChange.sink { [weak self] _ in
            DispatchQueue.main.async { self?.refreshAgentResults() }
        }
    }

    func reset() {
        wifiJoin = nil
        actionFeedback = nil
        files.cancel()
        // Changing the query already refreshes suggestions. Empty-query reopens still
        // refresh recency, which may have changed while the panel was hidden.
        if query.isEmpty { showSuggestions() }
        else { query = "" }
        selection = 0
    }

    func refreshForAppIndex() {
        guard isPresented, query.isEmpty || searchesAppIndex else { return }
        let selectedID = selectedRow?.id
        if query.isEmpty { showSuggestions() }
        else { refresh() }
        if let selectedID, let offset = rows.firstIndex(where: { $0.id == selectedID }) { selection = offset }
        else { selection = 0 }
    }

    private func showSuggestions() {
        let apps = index.suggestions(usage: usage).map { ResultRow.app($0) }
        sections = (apps.isEmpty ? [] : [ResultSection(title: "Suggestions", rows: apps)]) + [ResultSection(title: "Volant Commands", rows: CoreCommand.allCases.map(ResultRow.core) + [.settings, .reloadConfig])]
    }

    private func refresh() {
        searchesAppIndex = false
        selection = 0
        generation += 1
        let gen = generation
        immediate = []; contactRows = []; fileRows = []
        notice = nil
        actionFeedback = nil
        wifiJoin = nil
        files.cancel()
        let q = query.trimmingCharacters(in: .whitespaces)
        if !showingDictionary { dictionary.clear() }
        guard !q.isEmpty else { showSuggestions(); return }

        if let term = DictionaryQuery.term(query) { dictionary.input = term; sections = []; return }
        if showingTranslation { sections = []; return }
        if CaffeinateCommand.matches(q) { refreshCaffeinateResults(); return }
        if q.lowercased() == "emoji" { query = ":"; return }
        if ["volant settings", "reload", "reload config", "reload configuration"].contains(q.lowercased()) {
            sections = [ResultSection(title: "Volant", rows: [q.lowercased().contains("reload") ? .reloadConfig : .settings])]
            return
        }
        let settingTerms = q.lowercased().split(whereSeparator: { $0.isWhitespace })
        if settingTerms.count > 1 && settingTerms.contains("settings") {
            let panes = SystemSettingsDestination.search(q).map { ResultRow.systemSettings($0) }
            if !panes.isEmpty {
                sections = [ResultSection(title: "System Settings", rows: panes)]
                return
            }
        }
        if q.lowercased() == "notes" { sections = [ResultSection(title: "Notes", rows: notes.search("").map { .note($0) } + [.newNote("")])]; return }
        if connectivitySource != nil { refreshConnectivity(); return }
        if AudioRouteQuery(q) != nil { refreshAudioRoutes(); return }
        if VolumeCommand.matches(q) {
            refreshVolumeResults()
            return
        }
        if showingACP { sections = []; return }
        if showingAgents {
            refreshAgentResults()
            return
        }
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
            let rows = emojiSearch(String(q.dropFirst())).map { ResultRow.emoji($0) }
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

        searchesAppIndex = true
        var answers: [ResultRow] = []
        if let value = Calculator.evaluate(q) { answers.append(.calculation(Calculator.format(value))) }
        if let conv = UnitConverter.convert(q) { answers.append(.unit(UnitConverter.format(conv))) }
        immediate = []
        let builtins: [(String, ResultRow)] = [("Volant Settings", .settings), ("Reload Configuration", .reloadConfig)]
        let matchingCommands = CoreCommand.search(q).map(ResultRow.core) + builtins.filter { $0.0.localizedCaseInsensitiveContains(q) }.map { $0.1 }
        let words = q.split(separator: " ", maxSplits: 1).map(String.init)
        let head = words.first?.lowercased() ?? ""
        let tail = words.count > 1 ? words[1] : ""
        if let target = config.aliases[head] ?? config.aliases.sorted(by: { $0.key < $1.key }).first(where: { $0.key.lowercased() == head })?.value, words.count == 1, let app = index.resolveAlias(target) {
            immediate.append(ResultSection(title: "Alias", rows: [.app(app)]))
        }
        if !answers.isEmpty { immediate.append(ResultSection(title: "Answer", rows: answers)) }
        let snips = config.snippets.filter { $0.keyword.lowercased() == q.lowercased() }.map { ResultRow.snippet($0) }
        if !snips.isEmpty { immediate.append(ResultSection(title: "Snippets", rows: snips)) }
        let links = QuicklinkResolver.search(config.quicklinks, head).map { ResultRow.quicklink($0, query: tail) }
        if !links.isEmpty { immediate.append(ResultSection(title: "Quicklinks", rows: links)) }
        let aliased = Set(immediate.flatMap(\.rows).map(\.id))
        let apps = index.search(q, limit: 6, usage: usage).map { ResultRow.app($0) }.filter { !aliased.contains($0.id) }
        if !apps.isEmpty { immediate.append(ResultSection(title: "Applications", rows: apps)) }
        let panes = SystemSettingsDestination.search(q).map { ResultRow.systemSettings($0) }
        if !panes.isEmpty { immediate.append(ResultSection(title: "System Settings", rows: panes)) }
        if !matchingCommands.isEmpty { immediate.append(ResultSection(title: "Volant", rows: matchingCommands)) }
        compose(preservingSelection: false)

        let letters = q.filter(\.isLetter).count
        if searchesSecondarySources && letters >= 2 && q.count <= 40 {
            contacts.search(q, askIfNeeded: false) { [weak self] hits in
                let needle = q.lowercased()
                let tight = hits.filter { c in c.name.lowercased().split(separator: " ").contains { $0.hasPrefix(needle) } || c.name.lowercased().hasPrefix(needle) }
                self?.deliver(gen) { $0.contactRows = tight.prefix(3).map { .contact($0) } }
            }
        }
        if searchesSecondarySources && q.count >= 3 {
            files.search(q) { [weak self] hits in self?.deliver(gen) { $0.fileRows = hits.prefix(5).map { .file($0) } } }
        }
    }

    private func deliver(_ gen: Int, _ apply: (LauncherModel) -> Void) {
        guard gen == generation else { return }
        apply(self)
        compose()
    }

    /// Keeps the selected row by identity when async sections arrive above it.
    private func compose(preservingSelection: Bool = true) {
        let selectedID = preservingSelection ? selectedRow?.id : nil
        var out = immediate
        if !contactRows.isEmpty { out.append(ResultSection(title: "Contacts", rows: contactRows)) }
        if !fileRows.isEmpty { out.append(ResultSection(title: "Files", rows: fileRows)) }
        sections = out
        if let selectedID, let i = rows.firstIndex(where: { $0.id == selectedID }) { selection = i }
        else { selection = 0 }
    }

    private var connectivitySource: String? {
        let head = query.lowercased().split(whereSeparator: \.isWhitespace).first ?? ""
        if head == "wifi" || head == "wi-fi" { return "wifi" }
        if head == "bluetooth" || head == "bt" { return "bluetooth" }
        return nil
    }
    private func refreshConnectivity(force: Bool = false) {
        guard let source = connectivitySource else { return }
        let gen = generation
        let selectedID = force ? selectedRow?.id : nil
        let term = query.split(whereSeparator: \.isWhitespace).dropFirst().joined(separator: " ")
        sections = []; notice = "Loading…"
        connectivity.load(source, refresh: force) { [weak self] snapshot in
            guard let self, self.generation == gen else { return }
            let items = snapshot.items.filter { item in
                switch item {
                case .settings, .refresh: return true
                default: return term.isEmpty || item.title.localizedCaseInsensitiveContains(term)
                }
            }
            self.sections = [ResultSection(title: source == "wifi" ? "Wi-Fi Networks" : "Connected Bluetooth Devices", rows: items.map(ResultRow.connectivity))]
            if let selectedID, let index = self.rows.firstIndex(where: { $0.id == selectedID }) { self.selection = index }
            else { self.selection = 0 }
            self.actionFeedback = snapshot.items.isEmpty ? nil : snapshot.message
            self.notice = snapshot.message
        }
    }
    func joinWiFi(_ network: WiFiChoice, password: String?, useSaved: Bool) {
        guard !connectivityBusy else { return }
        connectivityBusy = true
        let gen = generation
        connectivity.join(network, password: password, useSaved: useSaved) { [weak self] error in
            guard let self else { return }
            self.connectivityBusy = false
            guard gen == self.generation else { return }
            if let error { self.actionFeedback = error }
            else {
                self.wifiJoin = nil
                self.refreshConnectivity(force: true)
                self.actionFeedback = "Connected to " + network.name
                self.searchFocusRequest = UUID()
            }
        }
    }

    private func refreshAudioRoutes() {
        guard let search = AudioRouteQuery(query) else { return }
        do {
            let routes = try audioRouting.routes().filter { search.directions.contains($0.direction) && (search.term.isEmpty || $0.name.localizedCaseInsensitiveContains(search.term)) }
            sections = search.directions.map { direction in
                ResultSection(title: direction.title, rows: routes.filter { $0.direction == direction }.map(ResultRow.audioRoute))
            }
            notice = routes.isEmpty ? "No matching audio devices. Connect the device and search again." : nil
        } catch { sections = []; notice = error.localizedDescription }
    }

    private func refreshVolumeResults() {
        do {
            let state = try volumeControl.state()
            let commands = VolumeCommand.parse(query, muted: state.muted)
            let volumeRows = commands.map { command -> ResultRow in
                let supported = (command == .mute || command == .unmute) ? state.canSetMute : state.canSetVolume
                let detail = supported ? (command == .up ? "+5%" : command == .down ? "−5%" : "") : "Hardware control only"
                return .volume(command, detail: detail)
            }
            sections = [ResultSection(title: "Volume · " + state.summary, rows: volumeRows)]
            notice = commands.isEmpty ? "Try volume up, volume down, mute, unmute, or volume 40%." : nil
        } catch {
            sections = []
            notice = error.localizedDescription
        }
    }

    private func refreshCaffeinateResults() {
        let selectedID = selectedRow?.id
        var commands = CaffeinateCommand.parse(query)
        if caffeinate.isActive { commands = [.off] }
        sections = [ResultSection(title: "Caffeinate", rows: commands.map(ResultRow.caffeinate))]
        notice = commands.isEmpty ? "Try caffeinate 30m, caffeinate 1h display, or caffeinate off (up to 24 hours)." : nil
        if let selectedID, let index = rows.firstIndex(where: { $0.id == selectedID }) { selection = index }
        else { selection = 0 }
    }

    func moveEmojiSelection(_ delta: Int) {
        guard !rows.isEmpty else { return }
        selection = min(max(0, selection + delta), rows.count - 1)
    }

    func moveSelection(_ delta: Int) {
        let count = rows.count
        guard count > 0 else { return }
        selection = (selection + delta + count) % count
    }

    var copyText: (String) -> Void = { text in
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(text, forType: .string)
    }

    private func copy(_ text: String) { copyText(text) }

    /// Clicks resolve the visible row's stable identity against the current results.
    /// A stale row must never fall back to index zero or launch a different app.
    func activate(rowID: String) {
        guard let index = rows.firstIndex(where: { $0.id == rowID }) else { return }
        selection = index
        activateSelection()
    }

    func activateSelection() {
        guard let row = selectedRow else { return }
        switch row {
        case .connectivity, .audioRoute, .volume, .extensionResult, .newNote, .calculation, .unit: break
        default: usage.record(key: row.id, query: query)
        }
        switch row {
        case .core(let command): query = command.query; return
        case .caffeinate(let command):
            let succeeded = caffeinate.perform(command)
            refreshCaffeinateResults()
            actionFeedback = succeeded ? nil : caffeinate.error
            return
        case .connectivity(let item):
            switch item {
            case .settings(let source): ConnectivityService.openSettings(source)
            case .refresh: refreshConnectivity(force: true)
            case .bluetooth: ConnectivityService.openSettings("bluetooth")
            case .wifi(let network):
                guard !connectivityBusy else { return }
                if network.current { refreshConnectivity(force: true) }
                else if network.security == "Managed / Other" { ConnectivityService.openSettings("wifi") }
                else if network.security == "Open" { joinWiFi(network, password: nil, useSaved: false) }
                else { wifiJoin = network; actionFeedback = nil }
            }
            return
        case .audioRoute(let route):
            do {
                try audioRouting.select(route)
                refreshAudioRoutes()
                if let index = rows.firstIndex(where: { $0.id == row.id }) { selection = index }
                else { selection = 0 }
                actionFeedback = route.direction.title + ": " + route.name
            } catch { actionFeedback = error.localizedDescription }
            return
        case .volume(let command, _):
            do {
                let state = try volumeControl.perform(command)
                refreshVolumeResults()
                if let index = rows.firstIndex(where: { $0.id == row.id }) { selection = index }
                else { selection = 0 }
                actionFeedback = state.summary
            } catch { actionFeedback = error.localizedDescription }
            return
        case .systemSettings(let pane):
            guard NSWorkspace.shared.open(pane.url) else {
                actionFeedback = "Couldn’t open " + pane.title + " in System Settings."
                return
            }
            dismiss(); return
        case .settings: dismiss(); onNote(.settings); return
        case .reloadConfig: dismiss(); onNote(.reloadConfig); return
        case .agentSession(let session): agents.focus(session); return
        case .agents: query = "agents"; return
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
            guard let url = QuicklinkResolver.url(for: link, query: query) else {
                notice = "This quicklink URL is invalid or unsupported. Check it in config.json."
                generation += 1
                files.cancel()
                sections = []
                return
            }
            guard QuicklinkResolver.open(url) else {
                notice = "Could not open this quicklink. Check that its app is installed."
                generation += 1
                files.cancel()
                sections = []
                return
            }
        }
        dismiss()
    }

    func editApp(_ app: AppEntry) {
        guard index.apps.contains(where: { $0.id == app.id }) else { return }
        dismiss()
        onNote(.editApp(app))
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
