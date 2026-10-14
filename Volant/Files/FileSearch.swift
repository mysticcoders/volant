import AppKit
import VolantCore

struct FileEntry: Identifiable, Hashable {
    let id: String
    let name: String
    let url: URL
    let kind: String
}

/// Debounced Spotlight file search within the user's home. Sandbox-safe: opening a hit hands the URL to the system.
/// With `fsearch` set (the owner turned on Use fsearch), a running fsearch daemon answers first, across
/// the whole disk with typo tolerance; if it can't, the same query falls back to Spotlight.
/// Not final so launcher tests can deliver fictional results without Spotlight.
class FileSearch: NSObject {
    enum Failure: Error { case unavailable }
    typealias SearchResult = Result<[FileEntry], Failure>
    private let startQuery: (NSMetadataQuery) -> Bool
    init(startQuery: @escaping (NSMetadataQuery) -> Bool = { $0.start() }) {
        self.startQuery = startQuery
        super.init()
    }
    deinit { query?.stop(); NotificationCenter.default.removeObserver(self) }
    private var query: NSMetadataQuery?
    private var completion: ((SearchResult) -> Void)?
    private var pending: DispatchWorkItem?
    /// Set while Use fsearch is on.
    var fsearch: FSearchClient?
    private var fsearchGeneration = 0

    func search(_ term: String, completion: @escaping (SearchResult) -> Void) {
        cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            if let fsearch = self.fsearch, term.trimmingCharacters(in: .whitespaces).count >= 2 { self.runFSearch(fsearch, term, completion: completion) }
            else { self.run(term, completion: completion) }
        }
        pending = work
        // fsearch answers in about a millisecond, so it needs only enough delay to skip keystrokes.
        DispatchQueue.main.asyncAfter(deadline: .now() + (fsearch == nil ? 0.15 : 0.05), execute: work)
    }

    /// Asks fsearch, keeping only the newest request's answer. Noisy paths are hidden as for Spotlight;
    /// an error falls back to Spotlight for the same term.
    private func runFSearch(_ fsearch: FSearchClient, _ term: String, completion: @escaping (SearchResult) -> Void) {
        fsearchGeneration += 1
        let generation = fsearchGeneration
        fsearch.search(term, limit: FSearch.maximumHits) { [weak self] result in
            guard let self, generation == self.fsearchGeneration else { return }
            switch result {
            case .success(let entries): completion(.success(Array(entries.filter { FileSearch.isInteresting($0.url.path) }.prefix(8))))
            case .failure: self.run(term, completion: completion)
            }
        }
    }

    func cancel() {
        pending?.cancel()
        pending = nil
        fsearchGeneration += 1
        stop()
    }

    private func run(_ term: String, completion: @escaping (SearchResult) -> Void) {
        pending = nil
        stop()
        guard term.count >= 3 else { completion(.success([])); return }
        let q = NSMetadataQuery()
        q.predicate = NSPredicate(format: "kMDItemFSName CONTAINS[cd] %@ AND kMDItemContentType != 'com.apple.application-bundle'", term)
        q.searchScopes = [NSMetadataQueryUserHomeScope]
        q.sortDescriptors = [NSSortDescriptor(key: NSMetadataItemFSContentChangeDateKey, ascending: false)]
        self.completion = completion
        query = q
        NotificationCenter.default.addObserver(self, selector: #selector(gathered(_:)), name: .NSMetadataQueryDidFinishGathering, object: q)
        if !startQuery(q) {
            stop()
            completion(.failure(.unavailable))
        }
    }

    @objc private func gathered(_ note: Notification) {
        guard let q = note.object as? NSMetadataQuery, q === query else { return }
        q.disableUpdates()
        var out: [FileEntry] = []
        for i in 0..<min(q.resultCount, 200) where out.count < 8 {
            guard let item = q.result(at: i) as? NSMetadataItem,
                  let path = item.value(forAttribute: NSMetadataItemPathKey) as? String,
                  FileSearch.isInteresting(path) else { continue }
            let url = URL(fileURLWithPath: path)
            let name = (item.value(forAttribute: NSMetadataItemDisplayNameKey) as? String) ?? url.lastPathComponent
            let kind = (item.value(forAttribute: kMDItemKind as String) as? String) ?? ""
            out.append(FileEntry(id: path, name: name, url: url, kind: kind))
        }
        let done = completion
        stop()
        done?(.success(out))
    }

    /// Hide library internals, caches, build products and dotfiles from the results.
    static func isInteresting(_ path: String) -> Bool {
        let noisy = ["/Library/", "/node_modules/", "/DerivedData/", "/.Trash/", "/dist/", "/target/", "/Pods/"]
        if noisy.contains(where: { path.contains($0) }) { return false }
        let parts = path.split(separator: "/")
        if parts.contains(where: { $0.hasPrefix(".") }) { return false }
        let directories = parts.dropLast().map { $0.lowercased() }
        return !directories.contains { $0 == "build" || $0.hasPrefix("build-") || $0.hasPrefix("build_") }
    }

    private func stop() {
        if let q = query {
            NotificationCenter.default.removeObserver(self, name: .NSMetadataQueryDidFinishGathering, object: q)
            q.stop()
        }
        query = nil
        completion = nil
    }

    static func open(_ entry: FileEntry) { NSWorkspace.shared.open(entry.url) }
    static func reveal(_ entry: FileEntry) { NSWorkspace.shared.activateFileViewerSelecting([entry.url]) }
}
