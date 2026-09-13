import AppKit
import SwiftUI

/// Floating notes window: one note with browsing and actions on demand. Stays up until closed.
final class NotesPanel: NSPanel {
    let store: NotesStore
    private let model: NotesModel

    init(store: NotesStore) {
        self.store = store
        self.model = NotesModel(store: store)
        super.init(contentRect: NSRect(x: 0, y: 0, width: 560, height: 620),
                   styleMask: [.titled, .closable, .resizable, .fullSizeContentView, .nonactivatingPanel, .utilityWindow],
                   backing: .buffered, defer: false)
        title = "Notes"
        titleVisibility = .hidden
        titlebarAppearsTransparent = true
        isMovableByWindowBackground = true
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        isReleasedWhenClosed = false
        hidesOnDeactivate = false
        minSize = NSSize(width: 380, height: 300)
        setFrameAutosaveName("VeyNotes")
        contentView = NSHostingView(rootView: NotesView(model: model).ignoresSafeArea(.container, edges: .top))
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    func toggle() {
        if isVisible && isKeyWindow { close(); return }
        store.reload()
        model.selectIfNeeded()
        if !isVisible, frameAutosaveName.isEmpty || frame.origin == .zero { center() }
        makeKeyAndOrderFront(nil)
    }

    func open(noteID: String) {
        store.reload()
        model.select(noteID)
        makeKeyAndOrderFront(nil)
    }

    func openNew(text: String = "") {
        let note = store.create(initialText: text)
        model.select(note.id)
        model.editing = true
        makeKeyAndOrderFront(nil)
    }

    override func cancelOperation(_ sender: Any?) {
        if model.overlay != nil { model.overlay = nil; return }
        close()
    }

    override func close() {
        store.flush()
        guard store.dirtyText.isEmpty else { return }
        orderOut(nil)
    }
}

final class NotesModel: ObservableObject {
    enum Overlay { case browse, actions }
    let store: NotesStore
    @Published var selectedID: String? {
        didSet { UserDefaults.standard.set(selectedID, forKey: preferenceKey + ".selected") }
    }
    @Published var editing = true
    @Published var liveMode = true
    @Published var filter = ""
    @Published var toast: String?
    @Published var overlay: Overlay?
    @Published private(set) var pinned: Set<String>
    private var preferenceKey: String { "notes." + store.directory.path }

    init(store: NotesStore) {
        self.store = store
        let key = "notes." + store.directory.path
        selectedID = UserDefaults.standard.string(forKey: key + ".selected")
        pinned = Set(UserDefaults.standard.stringArray(forKey: key + ".pinned") ?? [])
        selectIfNeeded()
    }

    var filtered: [Note] {
        store.search(filter, limit: Int.max).sorted {
            let left = pinned.contains($0.id), right = pinned.contains($1.id)
            if left != right { return left }
            if $0.modified != $1.modified { return $0.modified > $1.modified }
            return $0.id < $1.id
        }
    }
    var selected: Note? { store.notes.first { $0.id == selectedID } }

    func selectIfNeeded() {
        if selected == nil { selectedID = store.notes.first?.id }
    }

    func select(_ id: String) {
        store.flush()
        selectedID = id
        editing = true
        overlay = nil
    }

    func newNote(text: String = "") {
        store.flush()
        let note = store.create(initialText: text)
        filter = ""
        select(note.id)
    }

    func deleteSelected() {
        guard let id = selectedID else { return }
        store.delete(id)
        if !store.notes.contains(where: { $0.id == id }) {
            pinned.remove(id)
            persistPins()
            selectIfNeeded()
            editing = true
        }
    }

    func togglePin() {
        guard let id = selectedID else { return }
        if pinned.contains(id) { pinned.remove(id) } else { pinned.insert(id) }
        persistPins()
    }

    private func persistPins() {
        UserDefaults.standard.set(Array(pinned), forKey: preferenceKey + ".pinned")
    }

    func show(_ overlay: Overlay) {
        filter = ""
        self.overlay = overlay
    }

    func copyMarkdown() {
        guard let note = selected else { return }
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(note.text, forType: .string)
        flash("Copied Markdown")
    }

    func flash(_ message: String) {
        toast = message
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
            if self?.toast == message { self?.toast = nil }
        }
    }
}

enum NotesStyle {
    static let inset: CGFloat = 24
    static let controlSize: CGFloat = 28
    static let radius: CGFloat = 12
}

struct NotesView: View {
    @ObservedObject var model: NotesModel
    @ObservedObject var store: NotesStore
    @StateObject private var liveState: LiveEditorState

    init(model: NotesModel, liveState: LiveEditorState = LiveEditorState()) {
        self.model = model
        self.store = model.store
        self._liveState = StateObject(wrappedValue: liveState)
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            if let error = store.saveErrors.values.sorted().first ?? store.lastError {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "exclamationmark.triangle")
                    Text(error).font(.callout).textSelection(.enabled)
                    Spacer(minLength: 0)
                    if !store.saveErrors.isEmpty {
                        Button("Retry Save") { store.flush() }
                    } else {
                        Button("Dismiss") { store.lastError = nil }
                    }
                }
                .padding(12)
                .background(.quaternary)
                .padding(.horizontal, NotesStyle.inset)
            }
            document
            footer
        }
        .background(.regularMaterial)
        .overlay {
            if model.overlay != nil {
                GeometryReader { geometry in
                    ZStack(alignment: .top) {
                        Color.black.opacity(0.08).contentShape(Rectangle())
                            .onTapGesture { model.overlay = nil }
                        NotesPicker(model: model, store: store)
                            .frame(maxWidth: 420)
                            .frame(height: min(400, max(160, geometry.size.height - 80)))
                            .clipShape(RoundedRectangle(cornerRadius: 14))
                            .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Color.primary.opacity(0.1)))
                            .shadow(color: .black.opacity(0.18), radius: 18, y: 8)
                            .padding(.horizontal, 16).padding(.top, 54)
                    }
                }
            }
        }
        .background(shortcuts)
        .onChange(of: model.overlay) { _, value in
            if value == nil && model.editing { liveState.focus() }
        }
        .onChange(of: model.selectedID) { _, _ in liveState.context = nil }
        .onKeyPress(.escape) {
            if model.overlay != nil { model.overlay = nil }
            else { NSApp.keyWindow?.close() }
            return .handled
        }
    }

    private var header: some View {
        HStack(spacing: 6) {
            if let id = model.selectedID, model.pinned.contains(id) {
                Image(systemName: "pin.fill").font(.caption).foregroundStyle(.secondary)
            }
            Text(model.selected?.title ?? "Notes")
                .font(.system(size: 12, weight: .medium)).foregroundStyle(.secondary).lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
            HStack(spacing: 2) {
                control("Actions", symbol: "command", help: "Actions (⌘K)") { model.show(.actions) }
                    .keyboardShortcut("k", modifiers: .command)
                control("Browse notes", symbol: "square.on.square", help: "Browse notes (⌘P)") { model.show(.browse) }
                    .keyboardShortcut("p", modifiers: .command)
                control("New note", symbol: "plus", help: "New note (⌘N)") { model.newNote() }
                    .keyboardShortcut("n", modifiers: .command)
            }
            .padding(4)
            .background(Color.primary.opacity(0.045), in: Capsule())

        }
        .padding(.leading, 68).padding(.trailing, 12).padding(.vertical, 8)
    }

    @ViewBuilder private var document: some View {
        if let note = model.selected {
            if model.editing {
                ZStack(alignment: .topLeading) {
                    LiveMarkdownEditor(text: Binding(get: { store.notes.first { $0.id == note.id }?.text ?? "" },
                                                     set: { store.update(note.id, text: $0) }),
                                       live: model.liveMode, state: liveState)
                        .id(note.id)
                    if note.text.isEmpty {
                        Text("Start writing…").foregroundStyle(.tertiary)
                            .padding(.top, 12).allowsHitTesting(false)
                    }
                }
                .padding(.horizontal, NotesStyle.inset).padding(.top, 4)
            } else {
                MarkdownView(text: note.text) { _ in model.flash("Copied") }
            }
        } else {
            VStack(spacing: 14) {
                Image(systemName: "square.and.pencil").font(.largeTitle).foregroundStyle(.secondary)
                Text("A little space to think").font(.title3.weight(.medium))
                Text("Capture a thought, a list, or something to keep handy.")
                    .foregroundStyle(.secondary).multilineTextAlignment(.center)
                Button("Create a Note") { model.newNote() }
            }
            .padding(NotesStyle.inset)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var footer: some View {
        VStack(spacing: 8) {
            if model.editing && model.liveMode, let context = liveState.context {
                HStack(spacing: 8) {
                    Image(systemName: "chevron.left.forwardslash.chevron.right").foregroundStyle(.secondary)
                    Menu {
                        ForEach(CodeLanguage.allCases, id: \.self) { language in
                            Button { liveState.chooseLanguage(language) } label: {
                                if CodeLanguage.from(tag: context.fence.language) == language {
                                    Label(language.rawValue, systemImage: "checkmark")
                                } else { Text(language.rawValue) }
                            }
                        }
                    } label: {
                        Text(context.fence.language.isEmpty ? "Auto · " + context.detected.rawValue : CodeLanguage.from(tag: context.fence.language)?.rawValue ?? context.fence.language)
                    }
                    .menuStyle(.borderlessButton).fixedSize()
                    .accessibilityLabel("Code block language")
                    .help("Language for the code block at your cursor. Auto detects locally.")
                    Spacer(minLength: 0)
                    Button("Copy Code") { liveState.copyCode(); model.flash("Copied code") }
                        .buttonStyle(.borderless)
                }
                .font(.system(size: 12))
                .padding(.horizontal, 12).padding(.vertical, 8)
                .background(Color.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 9))
            }
            HStack {
                Text(model.toast ?? (!store.saveErrors.isEmpty ? "Not saved" : !store.dirtyText.isEmpty ? "Saving…" : ""))
                    .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                Spacer(minLength: 8)
                if let note = model.selected {
                    Text("\(note.text.split(whereSeparator: { $0.isWhitespace }).count) words")
                        .font(.caption).foregroundStyle(.tertiary)
                    Menu {
                        Button("Live") { model.liveMode = true; model.editing = true }
                        Button("Markdown Source") { model.liveMode = false; model.editing = true }
                        Button("Preview") { model.editing = false }
                    } label: {
                        Text(!model.editing ? "Preview" : model.liveMode ? "Live" : "Source")
                    }
                    .menuStyle(.borderlessButton).fixedSize()
                    .font(.system(size: 12, weight: .medium))
                    .accessibilityLabel("Editor mode")
                    .help("Live styles Markdown while you type. ⌘E toggles preview.")
                }
            }
        }
        .padding(.horizontal, NotesStyle.inset).padding(.top, 8).padding(.bottom, 12)
    }

    private func control(_ title: String, symbol: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).frame(width: NotesStyle.controlSize, height: NotesStyle.controlSize)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain).font(.system(size: 14, weight: .medium)).accessibilityLabel(title).help(help)
    }

    private var shortcuts: some View {
        Group {
            Button("Toggle Preview") { model.editing.toggle() }.keyboardShortcut("e", modifiers: .command)
            Button("Copy Markdown") { model.copyMarkdown() }.keyboardShortcut("c", modifiers: [.command, .shift])
            Button("Duplicate Note") { if let note = model.selected { model.newNote(text: note.text) } }.keyboardShortcut("d", modifiers: .command)
            Button("Pin Note") { model.togglePin() }.keyboardShortcut("p", modifiers: [.command, .shift])
            Button("Trash Note") { model.deleteSelected() }.keyboardShortcut(.delete, modifiers: .command)
        }
        .disabled(model.selected == nil || model.overlay != nil)
        .hidden().accessibilityHidden(true)
    }
}

struct NotesPicker: View {
    @ObservedObject var model: NotesModel
    @ObservedObject var store: NotesStore
    @State private var selection = 0
    @FocusState private var searchFocused: Bool

    private struct Entry: Identifiable {
        let id: String
        let title: String
        let subtitle: String
        let symbol: String
        let shortcut: String
        let action: () -> Void
    }

    private var entries: [Entry] {
        if model.overlay == .browse {
            return model.filtered.map { note in
                Entry(id: note.id, title: note.title,
                      subtitle: note.preview.isEmpty ? note.modified.formatted(date: .abbreviated, time: .shortened) : note.preview,
                      symbol: model.pinned.contains(note.id) ? "pin.fill" : "doc.text", shortcut: "") { model.select(note.id) }
            }
        }
        var actions = [Entry(id: "new", title: "New Note", subtitle: "", symbol: "plus", shortcut: "⌘N") { model.newNote() },
                       Entry(id: "browse", title: "Browse Notes", subtitle: "", symbol: "square.on.square", shortcut: "⌘P") { model.show(.browse) }]
        if let note = model.selected {
            actions += [
                Entry(id: "duplicate", title: "Duplicate Note", subtitle: "", symbol: "plus.square.on.square", shortcut: "⌘D") { model.newNote(text: note.text) },
                Entry(id: "pin", title: model.pinned.contains(note.id) ? "Unpin Note" : "Pin Note", subtitle: "", symbol: "pin", shortcut: "⇧⌘P") { model.togglePin() },
                Entry(id: "preview", title: model.editing ? "Preview Markdown" : "Return to Editor", subtitle: "", symbol: "eye", shortcut: "⌘E") { model.editing.toggle() },
                Entry(id: "copy", title: "Copy Markdown", subtitle: "", symbol: "doc.on.doc", shortcut: "⇧⌘C") { model.copyMarkdown() },
                Entry(id: "reveal", title: "Reveal in Finder", subtitle: "", symbol: "folder", shortcut: "") { store.flush(); NSWorkspace.shared.activateFileViewerSelecting([note.url]) },
                Entry(id: "trash", title: "Move to Trash", subtitle: "", symbol: "trash", shortcut: "⌘⌫") { model.deleteSelected() }
            ]
        }
        let term = model.filter.trimmingCharacters(in: .whitespacesAndNewlines)
        return actions.filter { term.isEmpty || $0.title.localizedCaseInsensitiveContains(term) }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField(model.overlay == .browse ? "Search notes…" : "Search actions…", text: $model.filter)
                    .textFieldStyle(.plain).focused($searchFocused)
                    .onSubmit { activate() }
                if !model.filter.isEmpty {
                    Button { model.filter = "" } label: { Image(systemName: "xmark.circle.fill") }
                        .buttonStyle(.borderless).accessibilityLabel("Clear search")
                }
                Button { model.overlay = nil } label: { Image(systemName: "xmark").font(.system(size: 11, weight: .medium)) }
                    .buttonStyle(.plain).foregroundStyle(.secondary)
                    .accessibilityLabel("Close picker").keyboardShortcut(.cancelAction)
            }
            .padding(16)
            Divider()
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 3) {
                        ForEach(Array(entries.enumerated()), id: \.element.id) { index, entry in
                            Button { activate(index) } label: {
                                HStack(spacing: 12) {
                                    Image(systemName: entry.symbol).frame(width: 20)
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(entry.title).lineLimit(1)
                                        if !entry.subtitle.isEmpty { Text(entry.subtitle).font(.caption).foregroundStyle(.secondary).lineLimit(1) }
                                    }
                                    Spacer(minLength: 4)
                                    Text(entry.shortcut).font(.caption).foregroundStyle(.secondary)
                                }
                                .padding(.horizontal, 12).padding(.vertical, 10).frame(maxWidth: .infinity, alignment: .leading)
                                .background(selection == index ? Color.primary.opacity(0.08) : .clear, in: RoundedRectangle(cornerRadius: NotesStyle.radius))
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain).id(index)
                        }
                        if entries.isEmpty {
                            VStack(spacing: 12) {
                                Text(model.overlay == .browse ? "No matching notes" : "No matching actions").foregroundStyle(.secondary)
                                if model.overlay == .browse { Button("Create a Note") { model.newNote() } }
                            }.padding(24)
                        }
                    }.padding(8)
                }
                .onChange(of: selection) { _, index in proxy.scrollTo(index) }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.regularMaterial)
        .onAppear { searchFocused = true }
        .onChange(of: model.filter) { _, _ in selection = 0 }
        .onChange(of: model.overlay) { _, _ in selection = 0; searchFocused = true }
        .onKeyPress(.downArrow) { selection = min(selection + 1, max(0, entries.count - 1)); return .handled }
        .onKeyPress(.upArrow) { selection = max(0, selection - 1); return .handled }
    }

    private func activate(_ index: Int? = nil) {
        let current = entries
        let index = index ?? selection
        guard current.indices.contains(index) else { return }
        let entry = current[index]
        model.overlay = nil
        entry.action()
    }
}
