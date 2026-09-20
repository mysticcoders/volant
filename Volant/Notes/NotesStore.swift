import Foundation
import Combine
import VolantCore

struct Note: Identifiable, Hashable {
    let id: String
    var url: URL
    var text: String
    var modified: Date
    var readError: String? = nil

    var title: String {
        if readError != nil { return url.lastPathComponent }
        let first = text.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }.first { !$0.isEmpty } ?? ""
        let cleaned = first.drop(while: { $0 == "#" }).trimmingCharacters(in: .whitespaces)
        return cleaned.isEmpty ? "Untitled" : String(cleaned.prefix(80))
    }

    var preview: String {
        if let readError { return readError }
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
    @Published private(set) var saveErrors: [String: String] = [:]
    @Published private(set) var loadError: String?
    var loadMessage: String? {
        if let loadError { return loadError }
        let count = notes.filter { $0.readError != nil }.count
        return count == 0 ? nil : "\(count) unreadable note\(count == 1 ? "" : "s"). Files and pins have been kept."
    }
    let directory: URL
    private let io = DispatchQueue(label: "com.mysticcoders.volant.notes", qos: .utility)
    private var pendingSave: [String: DispatchWorkItem] = [:]
    @Published private(set) var dirtyText: [String: String] = [:]

    init(directory: URL? = nil) {
        self.directory = directory ?? Preferences.supportDirectory.appendingPathComponent("Notes", isDirectory: true)
        try? FileManager.default.createDirectory(at: self.directory, withIntermediateDirectories: true)
        reload()
    }

    /// Re-reads the folder. Notes with unsaved edits keep their in-memory text; the disk copy never wins over a pending edit.
    func reload() {
        let fm = FileManager.default
        let urls: [URL]
        do {
            urls = try fm.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.contentModificationDateKey], options: [.skipsHiddenFiles])
            loadError = nil
        } catch {
            loadError = "The notes folder couldn’t be read. Existing notes and unsaved edits have been kept. Check folder access, then retry."
            return
        }
        var fresh = urls
            .filter { $0.pathExtension == "md" }
            .compactMap { url -> Note? in
                let id = url.lastPathComponent
                if let dirty = dirtyText[id] {
                    return Note(id: id, url: url, text: dirty, modified: Date())
                }
                guard let text = try? String(contentsOf: url, encoding: .utf8) else {
                    return Note(id: id, url: url, text: "", modified: notes.first { $0.id == id }?.modified ?? .distantPast,
                                readError: "This note couldn’t be read as UTF-8 Markdown. Check the file’s access and encoding, then retry.")
                }
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
            dirtyText[url.lastPathComponent] = initialText
            saveErrors[url.lastPathComponent] = "Could not create note: \(error.localizedDescription)"
        }
        let note = Note(id: url.lastPathComponent, url: url, text: initialText, modified: Date())
        notes.insert(note, at: 0)
        return note
    }

    func update(_ id: String, text: String) {
        guard let i = notes.firstIndex(where: { $0.id == id }), notes[i].readError == nil else { return }
        notes[i].text = text
        notes[i].modified = Date()
        dirtyText[id] = text
        let url = notes[i].url
        pendingSave[id]?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            let error = self.write(text, to: url)
            DispatchQueue.main.async { self.didWrite(text, id: id, error: error) }
        }
        pendingSave[id] = work
        io.asyncAfter(deadline: .now() + 0.4, execute: work)
    }

    private func write(_ text: String, to url: URL) -> String? {
        do {
            try text.write(to: url, atomically: true, encoding: .utf8)
            return nil
        } catch {
            return "Could not save note: \(error.localizedDescription)"
        }
    }

    private func didWrite(_ text: String, id: String, error: String?) {
        guard dirtyText[id] == text, notes.contains(where: { $0.id == id }) else { return }
        if let error { saveErrors[id] = error }
        else { dirtyText[id] = nil; saveErrors[id] = nil }
    }

    /// Retries every dirty note, including failed creation, and completes state updates before returning.
    func flush() {
        pendingSave.values.forEach { $0.cancel() }
        pendingSave.removeAll()
        io.sync {}
        for (id, text) in dirtyText {
            guard let url = notes.first(where: { $0.id == id })?.url else { continue }
            let error = io.sync { write(text, to: url) }
            didWrite(text, id: id, error: error)
        }
    }

    func delete(_ id: String) {
        guard let i = notes.firstIndex(where: { $0.id == id }), notes[i].readError == nil else { return }
        // Drain writes before trashing so a queued save cannot recreate the deleted file.
        flush()
        guard dirtyText[id] == nil else { return }
        let url = notes[i].url
        do {
            try FileManager.default.trashItem(at: url, resultingItemURL: nil)
            notes.remove(at: i)
            lastError = nil
        } catch {
            lastError = "Could not move note to Trash: \(error.localizedDescription)"
        }
    }

    func search(_ term: String, limit: Int = 8) -> [Note] {
        let t = term.trimmingCharacters(in: .whitespaces)
        guard !t.isEmpty else { return Array(notes.prefix(limit)) }
        return notes.filter { $0.text.localizedCaseInsensitiveContains(t) || ($0.readError != nil && $0.id.localizedCaseInsensitiveContains(t)) }.prefix(limit).map { $0 }
    }
}
