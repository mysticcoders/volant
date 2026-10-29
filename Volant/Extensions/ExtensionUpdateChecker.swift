import Foundation
import VolantCore

/// Extension updates the owner can see outside Settings, and the optional daily catalog check.
///
/// `available` reads only the signed catalog this Mac last accepted, saved by any check: it never
/// contacts the catalog, so the launcher can show it while the owner hasn't asked for anything. The
/// saved copy is verified again whenever it changes on disk.
///
/// The daily check runs only while `enabled` (Preferences.extensionUpdateChecks, off by default) and
/// at most once a day across all checks, manual ones included: a minute after launch, then hourly
/// while Volant runs, it checks only when the last accepted catalog is more than a day old. Like Check
/// for Updates, it turns off installed extensions the catalog revokes. It never installs or updates.
final class ExtensionUpdateChecker {
    var client = ExtensionCatalogClient.live
    var manager: () -> ExtensionManager = { ExtensionManager() }
    var enabled: () -> Bool = { false }
    var now: () -> Date = Date.init
    /// Called on the main queue after a background check accepted a catalog.
    var onCheck: () -> Void = {}
    static let interval: TimeInterval = 24 * 60 * 60
    private var timer: Timer?
    private var checking = false
    private var cache: (modified: Date, catalog: ExtensionCatalog?)?

    /// One installed extension with a newer version in the saved catalog.
    struct Update: Equatable {
        let name: String
        let version: String
    }

    /// Updates for installed extensions in the saved catalog, by name; none without a valid saved copy.
    func available() -> [Update] {
        guard let catalog = savedCatalog() else { return [] }
        let installed = manager().extensions
        return catalog.installable.compactMap { listing in
            guard case .update = ExtensionManager.catalogStatus(listing, installed: installed) else { return nil }
            return Update(name: listing.name, version: listing.version)
        }.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    private func savedCatalog() -> ExtensionCatalog? {
        let url = ExtensionCatalogState.indexURL(beside: client.stateURL)
        guard let modified = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate else { cache = nil; return nil }
        if let cache, cache.modified == modified { return cache.catalog }
        let catalog = client.cached()
        cache = (modified, catalog)
        return catalog
    }

    func start() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 60 * 60, repeats: true) { [weak self] _ in self?.checkIfDue() }
        DispatchQueue.main.asyncAfter(deadline: .now() + 60) { [weak self] in self?.checkIfDue() }
    }

    /// Checks the catalog when the daily check is on and no catalog was accepted in the last day.
    func checkIfDue() {
        guard enabled(), !checking else { return }
        if let last = ExtensionCatalogState.checked(at: client.stateURL), now().timeIntervalSince(last) < Self.interval { return }
        checking = true
        client.load { [weak self] result in
            guard let self else { return }
            self.checking = false
            guard case .success(let catalog) = result else { return }
            self.manager().applyRevocations(from: catalog)
            self.onCheck()
        }
    }
}
