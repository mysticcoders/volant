import Foundation
import Combine
import WidgetKit

/// Keeps the widgets and Shortcuts in step with the app: writes the notes snapshot to the App Group
/// a moment after the list or pins change, reloads widget timelines when it changed, and moves
/// notes the share extension left in the inbox into the notes folder.
@MainActor
final class ExtensionBridge {
    private let model: NotesModel
    private var changes: AnyCancellable?

    init(model: NotesModel) {
        self.model = model
        changes = model.store.$notes.combineLatest(model.$pinned)
            .debounce(for: .seconds(1), scheduler: DispatchQueue.main)
            .sink { [weak self] notes, pinned in self?.publish(notes, pinned: pinned) }
    }

    /// Titles and dates for every readable note, previews for the most recent few.
    private func publish(_ notes: [Note], pinned: Set<String>) {
        let ready = notes.filter { $0.readError == nil && !$0.downloading }.sorted { $0.modified > $1.modified }
        let items = ready.map { NotesSnapshot.Item(id: $0.id, title: $0.title, preview: NoteRow.plain($0.preview), modified: $0.modified, pinned: pinned.contains($0.id)) }
        let recent = Array((items.filter(\.pinned) + items.filter { !$0.pinned }).prefix(NotesSnapshot.recentLimit))
        let snapshot = NotesSnapshot(recent: recent, all: items.map { .init(id: $0.id, title: $0.title, preview: "", modified: $0.modified, pinned: $0.pinned) },
                                     inICloud: model.location.isICloud)
        if AppGroup.writeSnapshot(snapshot) { WidgetCenter.shared.reloadAllTimelines() }
    }

    /// Moves inbox notes into the notes folder, handing them to iCloud when that is where notes live.
    /// A note whose name is already taken stays in the inbox for the next try.
    func importInbox() {
        guard let inbox = AppGroup.inbox else { return }
        let folder = model.store.directory, toICloud = model.location.isICloud, store = model.store
        Task.detached(priority: .utility) {
            let fm = FileManager.default
            guard let urls = try? fm.contentsOfDirectory(at: inbox, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]) else { return }
            var moved = 0
            for url in urls where url.pathExtension == "md" {
                let target = folder.appendingPathComponent(url.lastPathComponent)
                guard !fm.fileExists(atPath: target.path) else { continue }
                do {
                    if toICloud { try fm.setUbiquitous(true, itemAt: url, destinationURL: target) } else { try fm.moveItem(at: url, to: target) }
                    moved += 1
                } catch {
                    continue
                }
            }
            if moved > 0 { await MainActor.run { store.reload() } }
        }
    }
}

extension AppRouter {
    /// Follows a `volant://` link from a widget, control, Shortcut or the share extension.
    func handle(_ link: DeepLink, model: NotesModel) {
        showingSettings = false
        switch link {
        case .newNote:
            newNote(in: model)
        case .note(let id):
            if !model.store.notes.contains(where: { $0.id == id }) { model.store.reload() }
            if model.store.notes.contains(where: { $0.id == id }) { open(noteID: id, in: model) } else { tab = .notes }
        case .search:
            tab = .search
        case .tool(let name):
            guard let tool = Tool(rawValue: name) else { return }
            if tool == .notes { tab = .notes; return }
            tab = .home
            toolPath = [tool]
        }
    }
}
