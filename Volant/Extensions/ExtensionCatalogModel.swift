import AppKit
import Combine
import VolantCore

/// Where the launcher shows the catalog: the query `catalog`, optionally followed by search text.
enum CatalogQuery {
    static func term(_ query: String) -> String? {
        let parts = query.trimmingCharacters(in: .whitespacesAndNewlines).split(maxSplits: 1, whereSeparator: \.isWhitespace)
        guard parts.first?.lowercased() == "catalog" else { return nil }
        return parts.count == 2 ? String(parts[1]).trimmingCharacters(in: .whitespacesAndNewlines) : ""
    }
}

/// The launcher's Extension Catalog: a searchable list of reviewed extensions with a detail pane.
/// The signed catalog is fetched only when the owner chooses Extension Catalog or Check Catalog,
/// never while typing, and is kept for the rest of the session. Installing goes through the verified
/// installer and never enables or runs anything.
final class ExtensionCatalogModel: ObservableObject {
    @Published var input = "" { didSet { if input != oldValue { keepSelectionVisible() } } }
    @Published private(set) var catalog: ExtensionCatalog?
    @Published private(set) var loading = false
    @Published private(set) var error: String?
    @Published private(set) var installing: String?
    @Published private(set) var feedback: String?
    @Published var selectedID: String?
    /// Bumped after installs so status and icons redraw from the manager's current list.
    @Published private(set) var revision = 0

    var client = ExtensionCatalogClient.live
    var manager: () -> ExtensionManager = { ExtensionManager() }
    var openSettings: () -> Void = {}
    var useExtension: (String) -> Void = { _ in }
    /// Asks to turn on an installed extension that is off, showing the hosts it needs first.
    var turnOn: (InstalledExtension) -> Void = { _ in }
    var openURL: (URL) -> Void = { NSWorkspace.shared.open($0) }

    /// Listings that are not revoked and match the search text by name, ID, summary, publisher or host.
    var listings: [ExtensionCatalog.Listing] {
        let term = input.trimmingCharacters(in: .whitespacesAndNewlines)
        return (catalog?.installable ?? []).filter { listing in
            term.isEmpty || ([listing.name, listing.id, listing.summary, listing.publisher] + listing.hosts)
                .contains { $0.localizedCaseInsensitiveContains(term) }
        }
    }

    var selected: ExtensionCatalog.Listing? {
        let visible = listings
        return visible.first { $0.id == selectedID } ?? visible.first
    }

    func installed(_ listing: ExtensionCatalog.Listing) -> InstalledExtension? {
        manager().extensions.first { $0.id == listing.id }
    }

    func status(_ listing: ExtensionCatalog.Listing) -> ExtensionManager.CatalogStatus {
        ExtensionManager.catalogStatus(listing, installed: manager().extensions)
    }

    var communityAllowed: Bool { manager().communityAllowed }

    /// The footer's Return label for the selected listing, or Check Catalog before loading.
    var primaryTitle: String {
        guard let selected else { return catalog == nil ? "Check Catalog" : "" }
        switch status(selected) {
        case .available: return communityAllowed ? "Install" : "Open Extension Settings"
        case .update: return communityAllowed ? "Update" : "Open Extension Settings"
        case .installed, .bundled:
            guard let ext = installed(selected), ext.enabled else { return communityAllowed || installed(selected)?.isCommunity == false ? "Turn On…" : "Open Extension Settings" }
            return "Use Extension"
        }
    }

    /// Fetches the signed catalog once per session; a failed check can be retried.
    func load() {
        guard !loading, catalog == nil else { return }
        loading = true; error = nil
        client.load { [weak self] result in
            guard let self else { return }
            self.loading = false
            switch result {
            case .success(let loaded):
                self.manager().applyRevocations(from: loaded)
                self.catalog = loaded; self.keepSelectionVisible()
            case .failure(let failure): self.error = failure.localizedDescription
            }
        }
    }

    func moveSelection(_ offset: Int) {
        let visible = listings
        guard !visible.isEmpty else { return }
        let current = visible.firstIndex { $0.id == selected?.id } ?? 0
        selectedID = visible[max(0, min(visible.count - 1, current + offset))].id
    }

    /// Return: check the catalog, install or update the selected listing, or use an installed one.
    func performPrimary() {
        guard catalog != nil else { load(); return }
        guard let listing = selected, installing == nil else { return }
        switch status(listing) {
        case .installed, .bundled:
            guard let ext = installed(listing) else { return }
            if ext.enabled { useExtension(listing.name) }
            else if ext.isCommunity && !communityAllowed { openSettings() }
            else { turnOn(ext) }
        case .available, .update:
            guard communityAllowed else { openSettings(); return }
            install(listing)
        }
    }

    func openSource() {
        guard let url = selected?.sourceURL else { return }
        openURL(url)
    }

    private func install(_ listing: ExtensionCatalog.Listing) {
        guard let catalog else { return }
        installing = listing.id; feedback = nil
        client.download(listing) { [weak self] result in
            guard let self else { return }
            self.installing = nil
            do {
                let files = try result.get()
                let manager = self.manager()
                guard manager.communityAllowed else { throw ExtensionManager.ExtensionError.communityDisabled }
                let installed = try manager.install(listing, manifest: files.manifest, module: files.module, icon: files.icon, from: catalog)
                self.feedback = "Installed \(installed.name). Choose Turn On to use it."
            } catch {
                self.feedback = error.localizedDescription
            }
            self.revision += 1
        }
    }

    private func keepSelectionVisible() {
        let visible = listings
        if !visible.contains(where: { $0.id == selectedID }) { selectedID = visible.first?.id }
    }

    /// Leaving the catalog keeps the loaded list for the session but forgets the search and messages.
    func leave() {
        input = ""; feedback = nil
    }
}
