import Foundation
import Combine

struct Note: Identifiable, Hashable {
    let id: String
    var url: URL
    var text: String
    var modified: Date

    var title: String {
        let first = text.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }.first { !$0.isEmpty } ?? ""
        let cleaned = first.drop(while: { $0 == "#" }).trimmingCharacters(in: .whitespaces)
        return cleaned.isEmpty ? "Untitled" : String(cleaned.prefix(80))
    }

    var preview: String {
        let lines = text.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        if let second = lines.dropFirst().first { return String(second) }
        return ""
    }
}

/// Plain Markdown files in a folder, one per note. Writes go through one serial queue; reload never
/// discards an edit that has not reached disk yet.
final class NotesStore: ObservableObject {
    @Published private(set) var notes: [Note] = []
    @Published var lastError: String? = nil
    let directory: URL
    private let io = DispatchQueue(label: "com.mysticcoders.vey.notes", qos: .utility)
    private var pendingSave: [String: DispatchWorkItem] = [:]
    private var dirtyText: [String: String] = [:]

    init(directory: URL? = nil) {
        self.directory = directory ?? Preferences.supportDirectory.appendingPathComponent("Notes", isDirectory: true)
        try? FileManager.default.createDirectory(at: self.directory, withIntermediateDirectories: true)
        reload()
    }

    /// Re-reads the folder. Notes with unsaved edits keep their in-memory text; the disk copy never wins over a pending edit.
    func reload() {
        let fm = FileManager.default
        let urls = (try? fm.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.contentModificationDateKey], options: [.skipsHiddenFiles])) ?? []
        var fresh = urls
            .filter { $0.pathExtension == "md" }
            .compactMap { url -> Note? in
                let id = url.lastPathComponent
                if let dirty = dirtyText[id] {
                    return Note(id: id, url: url, text: dirty, modified: Date())
                }
                guard let text = try? String(contentsOf: url, encoding: .utf8) else { return nil }
                let mod = (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                return Note(id: id, url: url, text: text, modified: mod)
            }
        let known = Set(fresh.map(\.id))
        for note in notes where dirtyText[note.id] != nil && !known.contains(note.id) { fresh.append(note) }
        notes = fresh.sorted { $0.modified > $1.modified }
    }

    /// Filenames are unique by construction: a date prefix for humans, a UUID suffix for safety.
    @discardableResult
    func create(initialText: String = "") -> Note {
        let day = Date().formatted(.iso8601.year().month().day())
        var url = directory.appendingPathComponent("\(day)-\(UUID().uuidString.prefix(8)).md")
        while FileManager.default.fileExists(atPath: url.path) {
            url = directory.appendingPathComponent("\(day)-\(UUID().uuidString.prefix(8)).md")
        }
        do {
            try initialText.write(to: url, atomically: true, encoding: .utf8)
        } catch {
            lastError = "Could not create note: \(error.localizedDescription)"
        }
        let note = Note(id: url.lastPathComponent, url: url, text: initialText, modified: Date())
        notes.insert(note, at: 0)
        return note
    }

    func update(_ id: String, text: String) {
        guard let i = notes.firstIndex(where: { $0.id == id }) else { return }
        notes[i].text = text
        notes[i].modified = Date()
        dirtyText[id] = text
        let url = notes[i].url
        pendingSave[id]?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.write(text, to: url, id: id) }
        pendingSave[id] = work
        io.asyncAfter(deadline: .now() + 0.4, execute: work)
    }

    /// Runs on the serial queue; clears the dirty marker only if no newer edit superseded this write.
    private func write(_ text: String, to url: URL, id: String) {
        do {
            try text.write(to: url, atomically: true, encoding: .utf8)
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                if self.dirtyText[id] == text { self.dirtyText[id] = nil }
            }
        } catch {
            DispatchQueue.main.async { [weak self] in self?.lastError = "Could not save note: \(error.localizedDescription)" }
        }
    }

    /// Writes every pending edit now, synchronously, in order. Safe to call from the main thread.
    func flush() {
        let pending = pendingSave
        pendingSave.removeAll()
        for (id, work) in pending {
            work.cancel()
            guard let text = dirtyText[id], let url = notes.first(where: { $0.id == id })?.url else { continue }
            io.sync { [weak self] in self?.write(text, to: url, id: id) }
        }
        io.sync {}
    }

    func delete(_ id: String) {
        guard let i = notes.firstIndex(where: { $0.id == id }) else { return }
        pendingSave[id]?.cancel()
        pendingSave[id] = nil
        dirtyText[id] = nil
        let url = notes[i].url
        do {
            try FileManager.default.trashItem(at: url, resultingItemURL: nil)
            notes.remove(at: i)
        } catch {
            lastError = "Could not move note to Trash: \(error.localizedDescription)"
        }
    }

    func search(_ term: String, limit: Int = 8) -> [Note] {
        let t = term.trimmingCharacters(in: .whitespaces)
        guard !t.isEmpty else { return Array(notes.prefix(limit)) }
        return notes.filter { $0.text.localizedCaseInsensitiveContains(t) }.prefix(limit).map { $0 }
    }
}
