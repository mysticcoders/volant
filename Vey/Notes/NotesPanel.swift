import AppKit
import SwiftUI

/// Floating notes window: a list of notes and an editor with live preview. Stays up until closed.
final class NotesPanel: NSPanel {
    let store: NotesStore
    private let model: NotesModel

    init(store: NotesStore) {
        self.store = store
        self.model = NotesModel(store: store)
        super.init(contentRect: NSRect(x: 0, y: 0, width: 720, height: 460),
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
        minSize = NSSize(width: 480, height: 300)
        setFrameAutosaveName("VeyNotes")
        contentView = NSHostingView(rootView: NotesView(model: model))
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    func toggle() {
        if isVisible && isKeyWindow { store.flush(); orderOut(nil); return }
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

    override func cancelOperation(_ sender: Any?) { store.flush(); orderOut(nil) }

    override func close() {
        store.flush()
        orderOut(nil)
    }
}

final class NotesModel: ObservableObject {
    let store: NotesStore
    @Published var selectedID: String?
    @Published var editing: Bool = false
    @Published var filter: String = ""
    @Published var toast: String? = nil

    init(store: NotesStore) { self.store = store }

    var filtered: [Note] { store.search(filter, limit: 500) }
    var selected: Note? { store.notes.first { $0.id == selectedID } }

    func selectIfNeeded() {
        if selectedID == nil || selected == nil { selectedID = store.notes.first?.id }
        if selected?.text.isEmpty ?? true { editing = true }
    }

    func select(_ id: String) {
        store.flush()
        selectedID = id
        editing = selected?.text.isEmpty ?? true
    }

    func newNote() {
        let note = store.create()
        selectedID = note.id
        editing = true
    }

    func deleteSelected() {
        guard let id = selectedID else { return }
        store.delete(id)
        selectedID = store.notes.first?.id
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
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { [weak self] in if self?.toast == message { self?.toast = nil } }
    }
}

struct NotesView: View {
    @ObservedObject var model: NotesModel
    @ObservedObject var store: NotesStore
    @FocusState private var editorFocused: Bool

    init(model: NotesModel) {
        self.model = model
        self.store = model.store
    }

    var body: some View {
        HStack(spacing: 0) {
            sidebar.frame(width: 220)
            Divider()
            editor
        }
        .background(.regularMaterial)
        .onKeyPress(.escape) { model.store.flush(); NSApp.keyWindow?.orderOut(nil); return .handled }
    }

    private var sidebar: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                TextField("Filter notes", text: $model.filter).textFieldStyle(.roundedBorder).font(.system(size: 12))
                Button { model.newNote() } label: { Image(systemName: "square.and.pencil") }
                    .buttonStyle(.borderless).keyboardShortcut("n", modifiers: .command).help("New note (⌘N)")
            }
            .padding(10)
            List(selection: $model.selectedID) {
                ForEach(model.filtered) { note in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(note.title).font(.system(size: 13, weight: .medium)).foregroundStyle(.primary).lineLimit(1)
                        Text(note.preview.isEmpty ? note.modified.formatted(date: .abbreviated, time: .shortened) : note.preview)
                            .font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
                    }
                    .padding(.vertical, 2)
                    .tag(note.id)
                }
            }
            .listStyle(.sidebar)
            .scrollContentBackground(.hidden)
            .onChange(of: model.selectedID) { _, new in if let new { model.select(new) } }
        }
    }

    private var editor: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Text(model.selected?.title ?? "No note").font(.system(size: 13, weight: .semibold)).lineLimit(1)
                Spacer()
                if let toast = model.toast { Text(toast).font(.system(size: 11)).foregroundStyle(.secondary).transition(.opacity) }
                Picker("", selection: $model.editing) {
                    Text("Preview").tag(false)
                    Text("Edit").tag(true)
                }
                .pickerStyle(.segmented).frame(width: 140)
                .keyboardShortcut("e", modifiers: .command)
                Button { model.copyMarkdown() } label: { Image(systemName: "doc.on.doc") }
                    .buttonStyle(.borderless).keyboardShortcut("c", modifiers: [.command, .shift]).help("Copy as Markdown (⇧⌘C)")
                Button { model.deleteSelected() } label: { Image(systemName: "trash") }
                    .buttonStyle(.borderless).keyboardShortcut(.delete, modifiers: .command).help("Move to Trash (⌘⌫)")
            }
            .padding(.horizontal, 12).padding(.vertical, 8)
            Divider()
            if let note = model.selected {
                if model.editing {
                    TextEditor(text: Binding(
                        get: { model.selected?.text ?? "" },
                        set: { store.update(note.id, text: $0) }))
                    .font(.system(size: 14, design: .monospaced))
                    .scrollContentBackground(.hidden)
                    .padding(8)
                    .focused($editorFocused)
                    .onAppear { DispatchQueue.main.async { editorFocused = true } }
                } else {
                    MarkdownView(text: note.text) { _ in model.flash("Copied") }
                }
            } else {
                VStack(spacing: 8) {
                    Text("No notes yet").foregroundStyle(.secondary)
                    Button("New Note") { model.newNote() }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }
}
