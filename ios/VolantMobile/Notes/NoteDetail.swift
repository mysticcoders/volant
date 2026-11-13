import SwiftUI

/// One note: a Markdown source editor or its rendered preview, with the Mac footer's save state and
/// word count. Edits go to the store as they are typed; the store debounces and serializes writes.
struct NoteDetail: View {
    @ObservedObject var model: NotesModel
    let id: String
    @Environment(\.volantTheme) private var theme
    @AppStorage("notes.preview") private var previewing = false
    @State private var text = ""
    @State private var loaded = false
    @FocusState private var focused: Bool

    private var store: NotesStore { model.store }
    private var note: Note? { model.selected }

    var body: some View {
        Group {
            if let note, note.readError != nil {
                ContentUnavailableView {
                    Label("Note unavailable", systemImage: "exclamationmark.triangle")
                } description: {
                    Text(note.preview)
                } actions: {
                    Button("Retry") { store.reload(); store.open(id); load() }
                }
            } else if let note, note.downloading {
                ProgressView("Downloading from iCloud…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if previewing {
                ScrollView {
                    MarkdownPreview(source: text).padding(NotesStyle.inset)
                }
            } else {
                TextEditor(text: $text)
                    .font(.system(.body, design: .default))
                    .scrollContentBackground(.hidden)
                    .contentMargins(.horizontal, NotesStyle.inset - 5, for: .scrollContent)
                    .contentMargins(.vertical, 12, for: .scrollContent)
                    .focused($focused)
                    .autocorrectionDisabled(false)
                    .padding(.horizontal, NotesStyle.inset - 5)
            }
        }
        .background(theme.background)
        .navigationTitle(note?.title ?? "")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button {
                    previewing.toggle()
                    if previewing { focused = false }
                } label: {
                    Image(systemName: previewing ? "pencil" : "eye")
                }
                .accessibilityLabel(previewing ? "Edit" : "Preview")
                .keyboardShortcut("e", modifiers: .command)
                Menu {
                    NoteActions(model: model, id: id)
                } label: {
                    Image(systemName: "ellipsis")
                }
                .accessibilityLabel("Actions")
            }
        }
        .safeAreaInset(edge: .bottom) {
            footer
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, NotesStyle.inset)
                .padding(.vertical, 6)
        }
        .onAppear(perform: load)
        .onChange(of: note?.downloading) { _, downloading in if downloading == false { load() } }
        .onChange(of: text) { _, newValue in
            guard loaded, newValue != store.text(of: id) else { return }
            store.update(id, text: newValue)
        }
    }

    /// Save trouble and word count; successful saves stay quiet, as on the Mac.
    @ViewBuilder
    private var footer: some View {
        if let error = store.saveErrors[id] {
            Button { store.flush() } label: {
                Label(error, systemImage: "exclamationmark.triangle").lineLimit(1)
            }
            .font(.caption)
            .tint(.red)
        } else {
            HStack(spacing: 8) {
                if store.dirtyText[id] != nil { Text("Saving…") }
                Text("\(text.split(whereSeparator: { $0.isWhitespace }).count) words")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .monospacedDigit()
        }
    }

    /// Loads the note's Markdown once per appearance; a new empty note starts with the keyboard up.
    private func load() {
        store.open(id)
        text = store.text(of: id) ?? ""
        loaded = true
        if text.isEmpty && !previewing { focused = true }
    }
}
