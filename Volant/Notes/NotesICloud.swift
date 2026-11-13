import Foundation
import VolantCore

/// Where notes live. Locally that is Application Support's Notes folder; while notes sync is on it is
/// the Notes folder in Volant's iCloud Drive container, which Volant for iPhone shares and which shows
/// in Finder as iCloud Drive > Volant > Notes.
enum NotesLocation {
    static let containerID = "iCloud.com.mysticcoders.volant"

    static var local: URL { Preferences.supportDirectory.appendingPathComponent("Notes", isDirectory: true) }

    /// The folder notes are in now, for backup export and import. Main thread only.
    static var current: URL = local

    static func cloudFolder(in container: URL) -> URL {
        container.appendingPathComponent("Documents/Notes", isDirectory: true)
    }

    /// Copies Markdown notes between folders through file coordination, which also downloads iCloud
    /// notes that are not on this Mac yet. A note already in the destination is replaced only when
    /// the source copy is newer. Returns the number of notes that could not be copied.
    @discardableResult
    static func copyNotes(from source: URL, to destination: URL, fileManager fm: FileManager = .default) -> Int {
        guard let urls = try? fm.contentsOfDirectory(at: source, includingPropertiesForKeys: [.contentModificationDateKey],
                                                     options: [.skipsHiddenFiles]) else { return 0 }
        try? fm.createDirectory(at: destination, withIntermediateDirectories: true)
        var failed = 0
        for url in urls where url.pathExtension == "md" {
            let target = destination.appendingPathComponent(url.lastPathComponent)
            if let existing = modified(target), let incoming = modified(url), existing >= incoming { continue }
            var coordinationError: NSError?
            var copyError: Error?
            NSFileCoordinator().coordinate(readingItemAt: url, options: [], writingItemAt: target, options: .forReplacing,
                                           error: &coordinationError) { from, to in
                do {
                    let data = try Data(contentsOf: from)
                    try data.write(to: to, options: .atomic)
                } catch { copyError = error }
            }
            if copyError != nil || coordinationError != nil { failed += 1 }
        }
        return failed
    }

    /// Renames a folder aside as `Notes before iCloud <stamp>`, keeping it as the backup of what this
    /// Mac had when sync was turned on. Nothing is renamed when the folder is missing or empty.
    @discardableResult
    static func setAside(_ folder: URL, fileManager fm: FileManager = .default, now: Date = Date()) -> URL? {
        guard let contents = try? fm.contentsOfDirectory(atPath: folder.path), !contents.isEmpty else { return nil }
        let stamp = now.formatted(.iso8601.year().month().day().dateSeparator(.dash).time(includingFractionalSeconds: false).timeSeparator(.omitted))
        let backup = folder.deletingLastPathComponent().appendingPathComponent("Notes before iCloud \(stamp)", isDirectory: true)
        do {
            try fm.moveItem(at: folder, to: backup)
            return backup
        } catch {
            return nil
        }
    }

    /// Carries pins and the remembered note, which are stored per folder, to a new folder that has none yet.
    static func carryPreferences(from old: URL, to new: URL, defaults: UserDefaults = .standard) {
        for suffix in [".pinned", ".selected"] {
            let from = "notes." + old.path + suffix, to = "notes." + new.path + suffix
            if defaults.object(forKey: to) == nil, let value = defaults.object(forKey: from) { defaults.set(value, forKey: to) }
        }
    }

    private static func modified(_ url: URL) -> Date? {
        try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
    }
}

/// Follows the "Sync settings and notes with iCloud" switch for notes. Turning it on copies this Mac's
/// notes into iCloud Drive, sets the local folder aside as a dated backup, and moves the store there.
/// Turning it off copies the iCloud notes back into a fresh local folder, so nothing is left only in
/// iCloud. Both moves copy on a background queue first, then copy again on the main queue after the
/// store's last edits have been flushed, so an edit made during the move is not lost.
final class NotesICloudSync {
    enum Status: Equatable {
        case off, moving, on, unavailable
        case attention(String)

        var text: String? {
            switch self {
            case .off: return nil
            case .moving: return String(localized: "Moving notes…", comment: "Notes iCloud sync status")
            case .on: return String(localized: "In iCloud Drive › Volant › Notes", comment: "Notes iCloud sync status; the value is a Finder location")
            case .unavailable: return String(localized: "Notes stay on this Mac until iCloud Drive is turned on.", comment: "Notes iCloud sync status")
            case .attention(let message): return message
            }
        }
    }

    private static let activeKey = "notes.iCloudActive"
    private let store: NotesStore
    private let defaults: UserDefaults
    private let resolveContainer: () -> URL?
    private let localFolder: URL
    private let makeWatcher: (URL, @escaping () -> Void) -> AnyObject?
    private var wanted: Bool?
    private var watcher: AnyObject?
    var onStatus: (Status) -> Void = { _ in }
    private(set) var status: Status = .off { didSet { if status != oldValue { onStatus(status) } } }

    /// `resolveContainer`, `localFolder` and `makeWatcher` are injected by tests so they never touch the
    /// owner's iCloud or notes, and never start a metadata query.
    init(store: NotesStore, defaults: UserDefaults = .standard, localFolder: URL = NotesLocation.local,
         resolveContainer: @escaping () -> URL? = { FileManager.default.url(forUbiquityContainerIdentifier: NotesLocation.containerID) },
         makeWatcher: @escaping (URL, @escaping () -> Void) -> AnyObject? = { NotesCloudWatcher(folder: $0, onChange: $1) }) {
        self.store = store
        self.defaults = defaults
        self.localFolder = localFolder
        self.resolveContainer = resolveContainer
        self.makeWatcher = makeWatcher
    }

    /// Follows the switch in config.json; repeated calls with the same value do nothing.
    func update(enabled: Bool) {
        guard wanted != enabled else { return }
        wanted = enabled
        if enabled { turnOn() } else { turnOff() }
    }

    private func turnOn() {
        status = .moving
        let local = localFolder, resolve = resolveContainer
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let container = resolve() else {
                DispatchQueue.main.async { if self?.wanted == true { self?.status = .unavailable } }
                return
            }
            let cloud = NotesLocation.cloudFolder(in: container)
            let failed = NotesLocation.copyNotes(from: local, to: cloud)
            DispatchQueue.main.async { self?.finishTurningOn(cloud: cloud, failedEarlier: failed) }
        }
    }

    private func finishTurningOn(cloud: URL, failedEarlier: Int) {
        guard wanted == true else { return }
        let previous = store.directory
        NotesLocation.carryPreferences(from: previous, to: cloud, defaults: defaults)
        guard store.relocate(to: cloud) else {
            status = .attention(String(localized: "Notes stayed on this Mac because a note couldn’t be saved. Retry the save, then turn sync off and on again.", comment: "Notes iCloud sync status"))
            wanted = nil
            return
        }
        let failed = NotesLocation.copyNotes(from: localFolder, to: cloud)
        if failed == 0 && failedEarlier == 0 { NotesLocation.setAside(localFolder) }
        store.reload()
        defaults.set(true, forKey: Self.activeKey)
        NotesLocation.current = cloud
        watcher = makeWatcher(cloud) { [weak self] in self?.store.reload() }
        status = failed == 0 ? .on : .attention(String(localized: "\(failed) notes couldn’t be copied to iCloud. They are still in the Notes folder on this Mac.", comment: "Notes iCloud sync status; needs a plural variant for one note"))
    }

    /// Restores notes to this Mac only if they were in iCloud before; a Mac that never synced notes is left alone.
    private func turnOff() {
        watcher = nil
        guard defaults.bool(forKey: Self.activeKey) else { status = .off; return }
        status = .moving
        let local = localFolder, resolve = resolveContainer
        let current = store.directory
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let cloud = current.standardizedFileURL != local.standardizedFileURL ? current : resolve().map(NotesLocation.cloudFolder(in:))
            let failed = cloud.map { NotesLocation.copyNotes(from: $0, to: local) }
            DispatchQueue.main.async { self?.finishTurningOff(cloud: cloud, failedEarlier: failed) }
        }
    }

    private func finishTurningOff(cloud: URL?, failedEarlier: Int?) {
        guard wanted == false else { return }
        guard let cloud, let failedEarlier else {
            status = .attention(String(localized: "iCloud notes couldn’t be reached, so they weren’t copied to this Mac. Sign in to iCloud, then turn sync on and off again.", comment: "Notes iCloud sync status"))
            store.relocate(to: localFolder)
            NotesLocation.current = localFolder
            return
        }
        NotesLocation.carryPreferences(from: cloud, to: localFolder, defaults: defaults)
        guard store.relocate(to: localFolder) else {
            status = .attention(String(localized: "Notes stayed in iCloud because a note couldn’t be saved. Retry the save, then turn sync on and off again.", comment: "Notes iCloud sync status"))
            wanted = nil
            return
        }
        let failed = failedEarlier + NotesLocation.copyNotes(from: cloud, to: localFolder)
        store.reload()
        NotesLocation.current = localFolder
        guard failed == 0 else {
            status = .attention(String(localized: "\(failed) iCloud notes couldn’t be copied to this Mac. They are still in iCloud Drive › Volant › Notes.", comment: "Notes iCloud sync status; needs a plural variant for one note"))
            return
        }
        defaults.set(false, forKey: Self.activeKey)
        status = .off
    }
}

/// Watches the iCloud notes folder and reloads the store when another device adds, changes or
/// removes a note. Notes that are not on this Mac yet are asked to download.
final class NotesCloudWatcher {
    private let query = NSMetadataQuery()
    private let folder: String
    private let onChange: () -> Void
    private var observers: [NSObjectProtocol] = []

    init(folder: URL, onChange: @escaping () -> Void) {
        self.folder = folder.standardizedFileURL.path
        self.onChange = onChange
        query.searchScopes = [NSMetadataQueryUbiquitousDocumentsScope]
        query.predicate = NSPredicate(format: "%K LIKE '*.md'", NSMetadataItemFSNameKey)
        for name in [NSNotification.Name.NSMetadataQueryDidFinishGathering, .NSMetadataQueryDidUpdate] {
            observers.append(NotificationCenter.default.addObserver(forName: name, object: query, queue: .main) { [weak self] _ in self?.refresh() })
        }
        query.start()
    }

    deinit {
        query.stop()
        observers.forEach(NotificationCenter.default.removeObserver)
    }

    private func refresh() {
        query.disableUpdates()
        defer { query.enableUpdates() }
        for case let item as NSMetadataItem in query.results {
            guard let url = item.value(forAttribute: NSMetadataItemURLKey) as? URL,
                  url.deletingLastPathComponent().standardizedFileURL.path == folder,
                  item.value(forAttribute: NSMetadataUbiquitousItemDownloadingStatusKey) as? String != NSMetadataUbiquitousItemDownloadingStatusCurrent
            else { continue }
            try? FileManager.default.startDownloadingUbiquitousItem(at: url)
        }
        onChange()
    }
}
