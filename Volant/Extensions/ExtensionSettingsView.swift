import SwiftUI
import VolantCore

/// Reloads whenever a window becomes key as well as on appear, so enabling an extension or allowing
/// hosts from the launcher shows here when Settings comes back, even if this pane never left the screen.
/// The catalog is fetched only when the owner chooses Refresh; fixtures pass `catalog` to start loaded.
struct ExtensionSettingsView: View {
    let configURL: URL
    let onChange: () -> Void
    var roots: [URL]?
    var directory: URL?
    var dataDirectory: URL?
    var catalogClient: ExtensionCatalogClient
    @State private var installed: [InstalledExtension] = []
    @State private var problems: [String] = []
    @State private var error: String?
    @State private var communityAllowed = false
    @State private var approvedHosts: [String] = []
    @State private var confirmingHosts: InstalledExtension?
    @State private var confirmingUninstall: InstalledExtension?
    @State private var confirmingClear: InstalledExtension?
    @State private var catalog: ExtensionCatalog?
    @State private var catalogLoading = false
    @State private var catalogError: String?
    @State private var installing: String?
    private let secretStore: ExtensionSecretStore
    init(configURL: URL, onChange: @escaping () -> Void, roots: [URL]? = nil, directory: URL? = nil, dataDirectory: URL? = nil,
         catalogClient: ExtensionCatalogClient = .live, catalog: ExtensionCatalog? = nil, secretStore: ExtensionSecretStore = .keychain) {
        self.configURL = configURL; self.onChange = onChange; self.roots = roots; self.directory = directory; self.dataDirectory = dataDirectory
        self.catalogClient = catalogClient; self.secretStore = secretStore
        _catalog = State(initialValue: catalog)
    }
    private var manager: ExtensionManager {
        let manager = ExtensionManager(configURL: configURL, roots: roots, directory: directory, dataDirectory: dataDirectory)
        manager.secretStore = secretStore
        return manager
    }
    private func reload() {
        let manager = manager; manager.reload()
        installed = manager.extensions; problems = manager.loadErrors; communityAllowed = manager.communityAllowed
        approvedHosts = ExtensionHostApprovals.approved(at: configURL).sorted()
    }
    private func setEnabled(_ ext: InstalledExtension, _ enabled: Bool) {
        do { try manager.setEnabled(ext, enabled); reload(); onChange() }
        catch { self.error = error.localizedDescription; reload() }
    }
    private func loadCatalog() {
        catalogLoading = true; catalogError = nil
        catalogClient.load { result in
            catalogLoading = false
            switch result {
            case .success(let loaded): catalog = loaded
            case .failure(let failure): catalogError = failure.localizedDescription
            }
        }
    }
    private func install(_ listing: ExtensionCatalog.Listing, from catalog: ExtensionCatalog) {
        installing = listing.id
        catalogClient.download(listing) { result in
            installing = nil
            do {
                let manager = manager
                guard manager.communityAllowed else { throw ExtensionManager.ExtensionError.communityDisabled }
                let files = try result.get()
                try manager.install(listing, manifest: files.manifest, module: files.module, icon: files.icon, from: catalog)
                reload(); onChange()
            } catch { self.error = error.localizedDescription; reload() }
        }
    }
    private func users(of host: String) -> [String] {
        installed.filter { $0.manifest.declaredHosts.contains(host) }.map(\.name)
    }
    var body: some View {
        Form {
            if communityAllowed {
                Section {
                    LabeledContent {
                        Button("Turn Off") { setCommunityAllowed(false) }
                            .accessibilityIdentifier("community-extensions-turn-off")
                    } label: {
                        Text("Community extensions are on")
                        Text("Turn off to stop every community extension at once. Your choices are kept for when you turn them back on.")
                    }
                }
            } else {
                communityIntro
            }
            Section {
                if visibleExtensions.isEmpty { Text("No extensions installed.").foregroundStyle(.secondary) }
                ForEach(visibleExtensions) { ext in extensionRow(ext) }
                ForEach(problems, id: \.self) { Text($0).foregroundStyle(.secondary) }
            } header: {
                HStack {
                    Text(communityAllowed ? "Installed" : "Built In")
                    Spacer()
                    if communityAllowed {
                        Button("Open Folder") { NSWorkspace.shared.open(ExtensionManager.directory) }.controlSize(.small).font(.callout)
                        Button("Refresh") { reload(); onChange(); loadCatalog() }.controlSize(.small).font(.callout)
                            .disabled(catalogLoading || installing != nil)
                            .accessibilityIdentifier("extension-refresh")
                    }
                }
            } footer: {
                SettingsFooter("Extensions start off and run only when you invoke them; changed code or permissions need enabling again. Turned-off extensions stay out of search; type ext and a name to find one. Uninstalling moves an extension to the Trash with its data and unused host access. Try Hello World: turn it on, then type hello Andrew")
            }
            if communityAllowed { catalogSection }
            if communityAllowed || !approvedHosts.isEmpty { networkAccessSection }
            if communityAllowed || !locationSharing.isEmpty { locationSection }
        }
        .formStyle(.settings)
        .onAppear(perform: reload)
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)) { _ in reload() }
        .sheet(item: $confirmingHosts) { ext in
            VStack(alignment: .leading, spacing: 16) {
                Text("Enable \(ext.name)?").font(.title2.bold())
                ExtensionHostList(hosts: ExtensionHostApprovals.missing(ext.manifest, at: configURL))
                HStack {
                    Spacer()
                    Button("Cancel") { confirmingHosts = nil }.keyboardShortcut(.cancelAction)
                    Button("Allow and Enable") { confirmingHosts = nil; setEnabled(ext, true) }.keyboardShortcut(.defaultAction)
                }
            }.padding(24).frame(width: 420).background(Color(nsColor: .windowBackgroundColor))
        }
        .alert("Uninstall \(confirmingUninstall?.name ?? "extension")?", isPresented: Binding(get: { confirmingUninstall != nil }, set: { if !$0 { confirmingUninstall = nil } })) {
            Button("Cancel", role: .cancel) { confirmingUninstall = nil }
            Button("Uninstall", role: .destructive) {
                guard let ext = confirmingUninstall else { return }
                confirmingUninstall = nil
                do { try manager.uninstall(ext); reload(); onChange() }
                catch { self.error = error.localizedDescription; reload() }
            }
        } message: {
            Text("Volant moves it to the Trash and removes host access that no other extension needs.")
        }
        .alert("Clear data for \(confirmingClear?.name ?? "extension")?", isPresented: Binding(get: { confirmingClear != nil }, set: { if !$0 { confirmingClear = nil } })) {
            Button("Cancel", role: .cancel) { confirmingClear = nil }
            Button("Clear Data", role: .destructive) {
                guard let ext = confirmingClear else { return }
                confirmingClear = nil
                do { try manager.clearStoredData(ext); reload() }
                catch { self.error = error.localizedDescription; reload() }
            }
        } message: {
            Text("Volant forgets what this extension saved on this Mac, such as pinned or hidden items. The extension stays installed and keeps its permissions.")
        }
        .alert("Couldn’t change extension", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
            Button("OK") { error = nil }
        } message: { Text(error ?? "") }
    }

    /// One installed extension: icon, name and details beside its switch, with its management buttons
    /// on a line of their own so the details keep their width at Settings' minimum size.
    private func extensionRow(_ ext: InstalledExtension) -> some View {
        let manager = manager
        let hasData = ext.manifest.usesStorage && manager.hasStoredData(ext)
        let hasSecrets = manager.hasSecrets(ext)
        return VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 10) {
                Group {
                    if let icon = ExtensionIcon.image(for: ext) {
                        Image(nsImage: icon).resizable().clipShape(RoundedRectangle(cornerRadius: 5))
                    } else {
                        Image(systemName: "puzzlepiece.extension").font(.system(size: 16)).foregroundStyle(.secondary)
                    }
                }.frame(width: 24, height: 24).accessibilityHidden(true)
                Toggle(isOn: Binding(get: { ext.enabled }, set: { enabled in
                    if enabled && !ExtensionHostApprovals.missing(ext.manifest, at: configURL).isEmpty { confirmingHosts = ext }
                    else { setEnabled(ext, enabled) }
                })) {
                    Text(ext.name)
                    Text((ext.isCommunity ? (ext.communityBlocked ? "Community · Blocked by master switch" : "Community") : "Bundled with Volant")
                         + (ext.catalogOrigin == nil ? "" : " · From catalog")
                         + " · Version \(ext.manifest.version) · " + ext.accessDescription
                         + (ext.enabled && !ExtensionHostApprovals.missing(ext.manifest, at: configURL).isEmpty ? " · Asks for host access on next use" : ""))
                }.disabled(ext.communityBlocked).accessibilityIdentifier("extension-toggle-" + ext.id)
            }
            if hasData || hasSecrets || ext.isCommunity {
                HStack(spacing: 8) {
                    if hasData {
                        Button("Clear Data…") { confirmingClear = ext }.controlSize(.small)
                            .accessibilityIdentifier("extension-clear-data-" + ext.id)
                    }
                    if hasSecrets {
                        Button("Remove Tokens") {
                            do { try manager.forgetSecrets(ext); reload() } catch { problems = [error.localizedDescription] }
                        }.controlSize(.small).help("Deletes this extension’s tokens from your Keychain; it asks again on next use.")
                            .accessibilityIdentifier("extension-remove-tokens-" + ext.id)
                    }
                    if ext.isCommunity {
                        Button("Uninstall…") { confirmingUninstall = ext }.controlSize(.small)
                            .accessibilityIdentifier("extension-uninstall-" + ext.id)
                    }
                }
                .padding(.leading, 34)
            }
        }
    }

    /// Community rows show only while the master switch is on; built-in extensions always show.
    private var visibleExtensions: [InstalledExtension] { communityAllowed ? installed : installed.filter { !$0.isCommunity } }
    private var locationSharing: [InstalledExtension] { let manager = manager; return installed.filter { manager.locationApproved($0) } }
    private var blockedCommunityCount: Int { installed.filter(\.isCommunity).count }

    private func setCommunityAllowed(_ allowed: Bool) {
        do { try manager.setCommunityAllowed(allowed, expected: communityAllowed); reload(); onChange() }
        catch { self.error = error.localizedDescription; reload() }
    }

    /// What Volant does to keep community extensions safe, and the one way to turn them on. Shown
    /// while they are off, in place of the catalog and community rows.
    @ViewBuilder private var communityIntro: some View {
        Section {
            VStack(alignment: .leading, spacing: 14) {
                Text("Community extensions run code written by other people. Here is how Volant keeps them in check:")
                    .fixedSize(horizontal: false, vertical: true)
                Grid(alignment: .topLeading, horizontalSpacing: 20, verticalSpacing: 14) {
                    GridRow {
                        CommunityPoint(symbol: "shield.lefthalf.filled", title: "Sandboxed",
                                       text: "Each runs as WebAssembly in a separate sandboxed helper, with no access to your files or the network.")
                        CommunityPoint(symbol: "checkmark.seal", title: "Reviewed and signed",
                                       text: "Catalog extensions are reviewed for Volant, and every download is checked against the signed catalog.")
                    }
                    GridRow {
                        CommunityPoint(symbol: "hand.raised", title: "You approve access",
                                       text: "Volant fetches only from sites you allow for each extension. Location needs its own approval.")
                        CommunityPoint(symbol: "chevron.left.forwardslash.chevron.right", title: "Source you can read",
                                       text: "Every catalog listing links to the exact source it was built from.")
                    }
                }
            }
            .padding(.vertical, 4)
            LabeledContent {
                Button("Turn On") { setCommunityAllowed(true) }
                    .buttonStyle(.borderedProminent)
                    .accessibilityIdentifier("community-extensions-turn-on")
            } label: {
                Text("Allow community extensions")
                Text(blockedCommunityCount == 0
                     ? "You choose which ones to install and turn on."
                     : "Your \(blockedCommunityCount) installed community \(blockedCommunityCount == 1 ? "extension comes" : "extensions come") back as you left \(blockedCommunityCount == 1 ? "it" : "them").")
            }
        } footer: {
            Link("Learn more about extension security", destination: URL(string: "https://usevolant.com/docs/privacy-and-security")!)
                .font(.callout)
        }
    }

    @ViewBuilder private var catalogSection: some View {
            Section {
                if let catalog {
                    if catalog.extensions.isEmpty { Text("The catalog has no extensions yet.").foregroundStyle(.secondary) }
                    // Installed rows already use extension IDs; sharing them in one Form misplaces rows.
                    ForEach(catalog.extensions, id: \.catalogRowID) { listing in catalogRow(listing, from: catalog) }
                } else if catalogLoading {
                    HStack(spacing: 8) { ProgressView().controlSize(.small); Text("Checking the catalog…").foregroundStyle(.secondary) }
                } else {
                    Text(catalogError ?? "Choose Refresh to check the catalog. Volant contacts it only then.").foregroundStyle(.secondary)
                }
            } header: {
                Text("Catalog")
            } footer: {
                SettingsFooter("Reviewed and signed for Volant, and each download is checked against the signed catalog. Installing never turns an extension on or runs it. Volant checks the catalog only when you choose Refresh; you can also type catalog in the launcher.")
            }
    }

    @ViewBuilder private var networkAccessSection: some View {
            Section {
                if approvedHosts.isEmpty { Text("No hosts allowed.").foregroundStyle(.secondary) }
                ForEach(approvedHosts, id: \.self) { host in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(host).font(.body.monospaced())
                            let names = users(of: host)
                            Text(names.isEmpty ? "Not used by any installed extension" : "Used by " + names.joined(separator: ", "))
                                .font(.callout).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button("Remove") {
                            do { try ExtensionHostApprovals.remove(host, at: configURL); reload(); onChange() }
                            catch { self.error = error.localizedDescription }
                        }.controlSize(.small).accessibilityIdentifier("extension-host-remove-" + host)
                    }
                }
            } header: {
                Text("Network Access")
            } footer: {
                SettingsFooter("Volant fetches from these hosts for network extensions, which have no network access themselves. Removing a host stops every extension that uses it until you allow it again.")
            }
    }

    @ViewBuilder private var locationSection: some View {
            Section {
                let sharing = locationSharing
                if sharing.isEmpty { Text("No extensions use your location.").foregroundStyle(.secondary) }
                ForEach(sharing) { ext in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(ext.name)
                            Text("Approximate location, about 11 km, shared with " + ext.manifest.declaredHosts.joined(separator: ", "))
                                .font(.callout).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button("Stop Sharing") {
                            do { try manager.stopSharingLocation(ext); reload(); onChange() }
                            catch { self.error = error.localizedDescription }
                        }.controlSize(.small).accessibilityIdentifier("extension-stop-location-" + ext.id)
                    }
                }
            } header: {
                Text("Location")
            } footer: {
                SettingsFooter("Each extension here was allowed your location separately. Volant asks macOS for it only when the extension runs, rounds it to about 11 km, and never saves it. Stopping makes the extension ask again on its next run.")
            }
    }
}

private extension ExtensionCatalog.Listing {
    var catalogRowID: String { "catalog:" + id }
}

extension ExtensionSettingsView {
    @ViewBuilder
    private func catalogRow(_ listing: ExtensionCatalog.Listing, from catalog: ExtensionCatalog) -> some View {
        let status = ExtensionManager.catalogStatus(listing, installed: installed)
        HStack(alignment: .top, spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(listing.name) + Text("  " + listing.version).foregroundColor(.secondary)
                Text(listing.summary).font(.callout)
                Text([listing.publisher, listing.license, InstalledExtension.accessDescription(capabilities: listing.capabilities, hosts: listing.hosts, storage: listing.storage == true)]
                    .joined(separator: " · ")).font(.callout).foregroundStyle(.secondary)
            }
            Spacer()
            if let source = listing.sourceURL {
                Button("Source") { NSWorkspace.shared.open(source) }.controlSize(.small)
                    .accessibilityIdentifier("extension-catalog-source-" + listing.id)
            }
            if installing == listing.id {
                ProgressView().controlSize(.small)
            } else {
                switch status {
                case .available, .update:
                    Button(status == .available ? "Install" : "Update") { install(listing, from: catalog) }
                        .controlSize(.small).disabled(!communityAllowed || installing != nil)
                        .accessibilityIdentifier("extension-catalog-install-" + listing.id)
                case .installed: Text("Installed").font(.callout).foregroundStyle(.secondary)
                case .bundled: Text("Bundled").font(.callout).foregroundStyle(.secondary)
                }
            }
        }
    }
}

struct ExtensionPermissionRequest: Identifiable {
    let id = UUID()
    let extensionItem: InstalledExtension
    let input: String
    var hosts: [String] = []
    /// Declared tokens not saved yet; the prompt asks for each before it can run.
    var secrets: [ExtensionSecret] = []
    /// The extension asks for the owner's location and has not been allowed it; Allow grants it to this
    /// extension only.
    var location = false
}

struct ExtensionPermissionView: View {
    let request: ExtensionPermissionRequest
    let enable: ([String: String]) -> Void
    let cancel: () -> Void
    @State private var values: [String: String] = [:]
    private var complete: Bool { request.secrets.allSatisfy { ExtensionSecret.isValidValue(values[$0.id, default: ""].trimmingCharacters(in: .whitespacesAndNewlines)) } }
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(request.extensionItem.enabled ? "Allow \(request.extensionItem.name) to go online?" : "Enable \(request.extensionItem.name)?")
                .font(.title2.bold())
            if request.hosts.isEmpty {
                Text(request.extensionItem.accessDescription)
            } else {
                ExtensionHostList(hosts: request.hosts)
            }
            if request.location {
                Label("Share your approximate location (about 11 km) with \(request.extensionItem.name) and the sites it reads. Volant asks macOS for it only when the extension runs, and never saves it.",
                      systemImage: "location").fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("extension-location-grant")
            }
            ForEach(request.secrets, id: \.id) { secret in
                ExtensionSecretField(secret: secret, value: Binding(get: { values[secret.id, default: ""] }, set: { values[secret.id] = $0 }))
            }
            Text("This extension will run now and stay enabled. You can turn it off, or remove its hosts, in Settings → Extensions.")
                .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            HStack {
                Spacer()
                Button("Cancel", action: cancel).keyboardShortcut(.cancelAction)
                Button(request.hosts.isEmpty && !request.location ? "Enable and Run" : "Allow and Run") { enable(values) }
                    .keyboardShortcut(.defaultAction).disabled(!complete)
            }
        }.padding(24).frame(width: 390)
            .background(Color(nsColor: .windowBackgroundColor))
    }
}

/// One token field in the first-run prompt, with where the token goes and that the extension never sees it.
struct ExtensionSecretField: View {
    let secret: ExtensionSecret
    @Binding var value: String
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(secret.title).font(.headline)
            SecureField(secret.title, text: $value).textFieldStyle(.roundedBorder).labelsHidden()
                .accessibilityIdentifier("extension-secret-\(secret.id)")
            Text((secret.help.map { $0 + " " } ?? "") + "Volant keeps it in your Keychain and adds it only to requests to \(secret.host). The extension never sees it.")
                .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// The hosts an extension needs, as shown before the owner allows them.
struct ExtensionHostList: View {
    let hosts: [String]
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("To use this extension, Volant needs to allow access to the following hosts:")
                .fixedSize(horizontal: false, vertical: true)
            ForEach(hosts, id: \.self) { host in
                Label(host, systemImage: "network").font(.body.monospaced())
            }
            Text("Volant fetches pages from these hosts for the extension. The extension itself has no network access.")
                .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// One point in the community extensions explanation: a symbol, a short title and a sentence.
private struct CommunityPoint: View {
    let symbol: String
    let title: String
    let text: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Image(systemName: symbol).foregroundStyle(.secondary).frame(width: 18).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.body.weight(.semibold))
                Text(text).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
