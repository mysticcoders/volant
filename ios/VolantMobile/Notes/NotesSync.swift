import Foundation

/// Where notes live: the Notes folder in Volant's iCloud Drive container when iCloud is available,
/// otherwise the local Documents folder. The container is public, so the same folder shows up as
/// iCloud Drive > Volant > Notes in Finder on the Mac and in the Files app.
enum NotesLocation {
    static let containerID = "iCloud.com.mysticcoders.volant"

    struct Resolved {
        let directory: URL
        let isICloud: Bool
    }

    /// Resolves the container off the main thread, as Apple requires, and moves any notes left in
    /// the local folder into iCloud. A note whose name already exists in iCloud stays local.
    static func resolve() async -> Resolved {
        await Task.detached(priority: .userInitiated) {
            let local = NotesStore.defaultDirectory
            guard let container = FileManager.default.url(forUbiquityContainerIdentifier: containerID) else {
                return Resolved(directory: local, isICloud: false)
            }
            let cloud = container.appendingPathComponent("Documents/Notes", isDirectory: true)
            try? FileManager.default.createDirectory(at: cloud, withIntermediateDirectories: true)
            migrate(from: local, to: cloud)
            return Resolved(directory: cloud, isICloud: true)
        }.value
    }

    /// Hands each local Markdown note to iCloud with setUbiquitous, which moves the file and starts its upload.
    private static func migrate(from local: URL, to cloud: URL) {
        let fm = FileManager.default
        guard let urls = try? fm.contentsOfDirectory(at: local, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]) else { return }
        for url in urls where url.pathExtension == "md" {
            let target = cloud.appendingPathComponent(url.lastPathComponent)
            guard !fm.fileExists(atPath: target.path) else { continue }
            try? fm.setUbiquitous(true, itemAt: url, destinationURL: target)
        }
    }
}

/// Watches the iCloud notes folder with a metadata query. Notes another device added or changed
/// arrive as placeholders until downloaded, so the watcher asks for each one to download and
/// reloads the store whenever iCloud reports a change.
@MainActor
final class NotesSync {
    private let query = NSMetadataQuery()
    private let directory: URL
    private let onChange: () -> Void
    private var observers: [NSObjectProtocol] = []

    init(directory: URL, onChange: @escaping () -> Void) {
        self.directory = directory
        self.onChange = onChange
        query.searchScopes = [NSMetadataQueryUbiquitousDocumentsScope]
        query.predicate = NSPredicate(format: "%K LIKE '*.md'", NSMetadataItemFSNameKey)
        let center = NotificationCenter.default
        for name in [NSNotification.Name.NSMetadataQueryDidFinishGathering, .NSMetadataQueryDidUpdate] {
            observers.append(center.addObserver(forName: name, object: query, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.refresh() }
            })
        }
        query.start()
    }

    deinit {
        query.stop()
        observers.forEach(NotificationCenter.default.removeObserver)
    }

    /// Requests download of every note in the folder that is not current, then reloads the list.
    private func refresh() {
        query.disableUpdates()
        defer { query.enableUpdates() }
        let folder = directory.standardizedFileURL.path
        for case let item as NSMetadataItem in query.results {
            guard let url = item.value(forAttribute: NSMetadataItemURLKey) as? URL,
                  url.deletingLastPathComponent().standardizedFileURL.path == folder else { continue }
            let status = item.value(forAttribute: NSMetadataUbiquitousItemDownloadingStatusKey) as? String
            if status != NSMetadataUbiquitousItemDownloadingStatusCurrent {
                try? FileManager.default.startDownloadingUbiquitousItem(at: url)
            }
        }
        onChange()
    }
}
