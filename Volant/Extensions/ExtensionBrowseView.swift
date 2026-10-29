import SwiftUI
import VolantCore

/// Settings → Extensions → Browse Extensions: the signed catalog in its own sheet, for finding and
/// installing extensions. Opening it checks the catalog once if Extensions has not already. Installed
/// listings say so, and updates are applied on the Extensions page rather than here. Revoked listings are
/// not shown. Installing never turns an extension on or runs it.
struct ExtensionBrowseView: View {
    let catalog: ExtensionCatalog?
    let loading: Bool
    let error: String?
    let installing: String?
    let installed: [InstalledExtension]
    let communityAllowed: Bool
    let load: () -> Void
    let install: (ExtensionCatalog.Listing) -> Void
    let done: () -> Void
    @State private var search = ""

    /// Listings matching the search text by name, ID, summary, publisher or host.
    private var listings: [ExtensionCatalog.Listing] {
        let term = search.trimmingCharacters(in: .whitespacesAndNewlines)
        return (catalog?.installable ?? []).filter { listing in
            term.isEmpty || ([listing.name, listing.id, listing.summary, listing.publisher] + listing.hosts)
                .contains { $0.localizedCaseInsensitiveContains(term) }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Text("Browse Extensions").font(.title2.bold())
                Spacer()
                TextField("Search", text: $search).textFieldStyle(.roundedBorder).frame(width: 200)
                    .accessibilityIdentifier("extension-browse-search")
            }
            .padding(20)
            Divider()
            content.frame(maxWidth: .infinity, maxHeight: .infinity)
            Divider()
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text("Reviewed and signed for Volant; each download is checked against the signed catalog. Installing never turns an extension on or runs it.")
                    .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                Spacer()
                Button("Done", action: done).keyboardShortcut(.defaultAction).accessibilityIdentifier("extension-browse-done")
            }
            .padding(20)
        }
        .frame(width: 620, height: 520)
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear { if catalog == nil && !loading { load() } }
    }

    @ViewBuilder private var content: some View {
        if let catalog {
            if listings.isEmpty {
                Text(catalog.installable.isEmpty ? "The catalog has no extensions yet." : "No extensions match “\(search)”.")
                    .foregroundStyle(.secondary)
            } else {
                List(listings) { listing in row(listing) }
                    .scrollContentBackground(.hidden)
            }
        } else if loading {
            HStack(spacing: 8) { ProgressView().controlSize(.small); Text("Checking the catalog…").foregroundStyle(.secondary) }
        } else {
            VStack(spacing: 12) {
                Text(error ?? String(localized: "The catalog hasn’t been checked.", comment: "Browse Extensions status")).foregroundStyle(.secondary).multilineTextAlignment(.center)
                Button("Try Again", action: load).accessibilityIdentifier("extension-browse-retry")
            }.padding(40)
        }
    }

    /// One listing: name, version, summary, publisher, license and the access it asks for, with its
    /// source link and install state.
    private func row(_ listing: ExtensionCatalog.Listing) -> some View {
        HStack(alignment: .top, spacing: 10) {
            CatalogIcon(listing: listing, installed: installed.first { $0.id == listing.id }, size: 24)
            VStack(alignment: .leading, spacing: 3) {
                Text(listing.name).font(.body.weight(.semibold)) + Text("  " + listing.version).foregroundColor(.secondary)
                Text(listing.summary).fixedSize(horizontal: false, vertical: true)
                Text([listing.publisher, listing.license,
                      InstalledExtension.accessDescription(capabilities: listing.capabilities, hosts: listing.hosts, storage: listing.storage == true)]
                    .joined(separator: " · ")).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            if let source = listing.sourceURL {
                Button("Source") { NSWorkspace.shared.open(source) }.controlSize(.small)
                    .accessibilityIdentifier("extension-catalog-source-" + listing.id)
            }
            action(listing).frame(minWidth: 70, alignment: .trailing)
        }
        .padding(.vertical, 6)
    }

    @ViewBuilder private func action(_ listing: ExtensionCatalog.Listing) -> some View {
        if installing == listing.id {
            ProgressView().controlSize(.small)
        } else {
            switch ExtensionManager.catalogStatus(listing, installed: installed) {
            case .available:
                Button("Install") { install(listing) }.controlSize(.small)
                    .disabled(!communityAllowed || installing != nil)
                    .accessibilityIdentifier("extension-catalog-install-" + listing.id)
            case .update:
                Text("Update in Extensions").font(.callout).foregroundStyle(.secondary)
            case .installed:
                Text("Installed").font(.callout).foregroundStyle(.secondary)
            case .bundled:
                Text("Bundled").font(.callout).foregroundStyle(.secondary)
            }
        }
    }
}
