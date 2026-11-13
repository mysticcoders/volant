import Foundation
import Combine
import UIKit

/// Selection, pins and the browse filter for the notes list, following the Mac NotesModel: pins
/// and the last selection are kept in UserDefaults scoped to the notes folder, and the filter
/// answers at once from titles and previews, then from a background full-text scan.
@MainActor
final class NotesModel: ObservableObject {
    let store: NotesStore
    let location: NotesLocation.Resolved
    private let defaults: UserDefaults
    @Published var selectedID: String? {
        didSet {
            guard selectedID != oldValue else { return }
            store.flush()
            defaults.set(selectedID, forKey: preferenceKey + ".selected")
            store.open(selectedID)
        }
    }
    @Published var filter = "" { didSet { if filter != oldValue { searchFiles() } } }
    @Published private(set) var pinned: Set<String>
    @Published private var fileMatches: FileMatches?
    private var fileSearch: NotesSearchTask?
    private var storeChanges: AnyCancellable?
    private var preferenceKey: String { "notes." + store.directory.path }

    /// Full-text matches for one filter, valid while the store's list is unchanged.
    private struct FileMatches {
        let filter: String
        let generation: Int
        let notes: [Note]
    }

    /// `defaults` holds the remembered selection and pins; tests pass an isolated suite.
    init(store: NotesStore, location: NotesLocation.Resolved, defaults: UserDefaults = .standard) {
        self.store = store
        self.location = location
        self.defaults = defaults
        let key = "notes." + store.directory.path
        pinned = Set(defaults.stringArray(forKey: key + ".pinned") ?? [])
        storeChanges = store.objectWillChange.sink { [weak self] in self?.objectWillChange.send() }
    }

    /// Notes for the list: pinned first, then most recently modified, narrowed by the filter.
    var filtered: [Note] {
        let found: [Note]
        if let matches = fileMatches, matches.filter == filter, matches.generation == store.generation { found = matches.notes }
        else { found = store.search(filter, limit: Int.max) }
        return found.sorted {
            let left = pinned.contains($0.id), right = pinned.contains($1.id)
            if left != right { return left }
            if $0.modified != $1.modified { return $0.modified > $1.modified }
            return $0.id < $1.id
        }
    }

    var selected: Note? { store.notes.first { $0.id == selectedID } }

    /// The note the app last showed, restored on launch on wide layouts where the editor is visible.
    var rememberedID: String? { defaults.string(forKey: preferenceKey + ".selected") }

    /// Cancels the previous filter's file scan and starts one for the current filter.
    private func searchFiles() {
        fileSearch?.cancel()
        fileMatches = nil
        let filter = filter
        fileSearch = store.searchFiles(filter, limit: Int.max) { [weak self] notes in
            guard let self, self.filter == filter else { return }
            self.fileMatches = FileMatches(filter: filter, generation: self.store.generation, notes: notes)
        }
    }

    func newNote(text: String = "") {
        store.flush()
        let note = store.create(initialText: text)
        filter = ""
        selectedID = note.id
    }

    func duplicate(_ id: String) {
        guard let text = store.text(of: id) else { return }
        newNote(text: text)
    }

    func delete(_ id: String) {
        store.delete(id)
        guard !store.notes.contains(where: { $0.id == id }) else { return }
        pinned.remove(id)
        persistPins()
        if selectedID == id { selectedID = nil }
    }

    func togglePin(_ id: String) {
        if pinned.contains(id) { pinned.remove(id) } else { pinned.insert(id) }
        persistPins()
    }

    func copyMarkdown(_ id: String) {
        guard let text = store.text(of: id) else { return }
        UIPasteboard.general.string = text
    }

    private func persistPins() {
        defaults.set(Array(pinned), forKey: preferenceKey + ".pinned")
    }
}
