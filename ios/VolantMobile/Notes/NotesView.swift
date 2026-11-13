import SwiftUI

/// Shared metrics, matching the Mac notes surface.
enum NotesStyle {
    static let inset: CGFloat = 20
    static let radius: CGFloat = 12
}

/// The notes split view: the browsable list, and one note filling the detail column. On iPhone
/// the list pushes the note; on iPad both columns show and the last note is restored.
struct NotesView: View {
    @ObservedObject var model: NotesModel
    @ObservedObject var themes: ThemeStore
    @Environment(\.volantTheme) private var theme
    @Environment(\.horizontalSizeClass) private var sizeClass

    var body: some View {
        NavigationSplitView {
            NotesList(model: model)
                .navigationTitle("Notes")
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button { model.newNote() } label: { Image(systemName: "square.and.pencil") }
                            .accessibilityLabel("New Note")
                            .keyboardShortcut("n", modifiers: .command)
                    }
                }
        } detail: {
            if let id = model.selectedID, model.selected != nil {
                NoteDetail(model: model, id: id).id(id)
            } else {
                EmptyNoteView { model.newNote() }
            }
        }
        .onAppear {
            if sizeClass == .regular, model.selectedID == nil {
                model.selectedID = model.rememberedID.flatMap { id in model.store.notes.first { $0.id == id }?.id }
                    ?? model.store.notes.first?.id
            }
        }
    }
}

/// The list of notes: pinned first, searchable by title, preview and full text.
struct NotesList: View {
    @ObservedObject var model: NotesModel
    @Environment(\.volantTheme) private var theme

    var body: some View {
        let notes = model.filtered
        List(selection: $model.selectedID) {
            if let message = model.store.loadMessage {
                Label(message, systemImage: "exclamationmark.triangle").font(.callout)
            }
            ForEach(NoteGroup.group(notes, pinned: model.pinned)) { group in
                Section(group.title) {
                    rows(group.notes)
                }
            }
        }
        .overlay {
            if notes.isEmpty {
                if model.filter.isEmpty {
                    ContentUnavailableView("No Notes", systemImage: "square.and.pencil", description: Text("A little space to think"))
                } else {
                    ContentUnavailableView.search(text: model.filter)
                }
            }
        }
        .scrollContentBackground(theme.hasPalette ? .hidden : .automatic)
        .background(theme.hasPalette ? theme.background : nil)
        .searchable(text: $model.filter, prompt: "Search Notes")
        .refreshable { model.store.reload() }
    }

    /// Rows for one date group, with pin and trash swipes and the note actions menu.
    private func rows(_ notes: [Note]) -> some View {
        ForEach(notes) { note in
            NoteRow(note: note, pinned: model.pinned.contains(note.id))
                .tag(note.id)
                .listRowBackground(theme.hasPalette ? theme.raisedSurface : nil)
                .swipeActions(edge: .leading) {
                    Button { model.togglePin(note.id) } label: {
                        Label(model.pinned.contains(note.id) ? "Unpin" : "Pin", systemImage: model.pinned.contains(note.id) ? "pin.slash" : "pin")
                    }
                    .tint(Brand.rust)
                }
                .swipeActions(edge: .trailing) {
                    Button(role: .destructive) { model.delete(note.id) } label: { Label("Trash", systemImage: "trash") }
                }
                .contextMenu { NoteActions(model: model, id: note.id) }
        }
    }
}

/// Notes grouped for the list: pinned first, then Today, Yesterday, the previous week and month,
/// and older notes by month.
struct NoteGroup: Identifiable {
    let title: String
    let notes: [Note]
    var id: String { title }

    static func group(_ notes: [Note], pinned: Set<String>, now: Date = Date(), calendar: Calendar = .current) -> [NoteGroup] {
        var order: [String] = []
        var buckets: [String: [Note]] = [:]
        let today = calendar.startOfDay(for: now)
        func title(for note: Note) -> String {
            if pinned.contains(note.id) { return String(localized: "Pinned") }
            let day = calendar.startOfDay(for: note.modified)
            let days = calendar.dateComponents([.day], from: day, to: today).day ?? 0
            switch days {
            case ..<1: return String(localized: "Today")
            case 1: return String(localized: "Yesterday")
            case 2..<7: return String(localized: "Previous 7 Days")
            case 7..<30: return String(localized: "Previous 30 Days")
            default: return note.modified.formatted(.dateTime.month(.wide).year())
            }
        }
        for note in notes {
            let key = title(for: note)
            if buckets[key] == nil { order.append(key) }
            buckets[key, default: []].append(note)
        }
        return order.map { NoteGroup(title: $0, notes: buckets[$0] ?? []) }
    }
}

struct NoteRow: View {
    let note: Note
    let pinned: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 6) {
                if pinned { Image(systemName: "pin.fill").font(.caption).foregroundStyle(.tint) }
                if note.readError != nil { Image(systemName: "exclamationmark.triangle").font(.caption).foregroundStyle(.orange) }
                Text(note.title).font(.headline).lineLimit(1)
            }
            HStack(spacing: 6) {
                Text(note.modified, format: .relative(presentation: .named)).monospacedDigit()
                if !note.preview.isEmpty { Text(Self.plain(note.preview)).lineLimit(1) }
            }
            .font(.subheadline)
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
    }

    /// The preview line without list, quote and emphasis markers, so rows read as prose.
    static func plain(_ line: String) -> String {
        var text = line[...]
        for prefix in ["- [ ] ", "- [x] ", "- ", "* ", "+ ", "> "] where text.hasPrefix(prefix) {
            text = text.dropFirst(prefix.count)
            break
        }
        return text.filter { !"*_`".contains($0) }
    }
}

/// Note commands shared by the row context menu and the editor's Actions menu, mirroring the Mac Actions overlay.
struct NoteActions: View {
    @ObservedObject var model: NotesModel
    let id: String

    var body: some View {
        let pinned = model.pinned.contains(id)
        Button { model.togglePin(id) } label: { Label(pinned ? "Unpin Note" : "Pin Note", systemImage: pinned ? "pin.slash" : "pin") }
        Button { model.copyMarkdown(id) } label: { Label("Copy Markdown", systemImage: "doc.on.doc") }
        Button { model.duplicate(id) } label: { Label("Duplicate", systemImage: "plus.square.on.square") }
        if let text = model.store.text(of: id) {
            ShareLink(item: text) { Label("Share", systemImage: "square.and.arrow.up") }
        }
        Divider()
        Button(role: .destructive) { model.delete(id) } label: { Label("Move to Trash", systemImage: "trash") }
    }
}

/// The empty detail column, with the Volant wing and the Mac notes empty-state copy.
struct EmptyNoteView: View {
    let create: () -> Void
    @Environment(\.volantTheme) private var theme

    var body: some View {
        VStack(spacing: 14) {
            Image("VolantWing")
                .resizable()
                .scaledToFit()
                .frame(width: 56, height: 56)
                .foregroundStyle(.tint)
            Text("A little space to think").font(.title3.weight(.medium))
            Button("New Note", systemImage: "square.and.pencil", action: create)
                .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(theme.background)
    }
}
