import SwiftUI
import VolantCore

/// Installed extensions, with updates from the signed catalog applied here; Browse opens the catalog in
/// its own sheet for finding new ones. Reloads whenever a window becomes key as well as on appear, so
/// enabling an extension or allowing hosts from the launcher shows here when Settings comes back, even if
/// this pane never left the screen. The catalog is fetched only when the owner chooses Check for Updates
/// or Browse; fixtures pass `catalog` to start loaded.
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
    @State private var updatingAll = false
    @State private var notices: [String] = []
    @State private var browsing = false
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
    /// Fetches the signed catalog and turns off any installed extension it revokes.
    private func loadCatalog() {
        catalogLoading = true; catalogError = nil; notices = []
        catalogClient.load { result in
            catalogLoading = false
            switch result {
            case .success(let loaded):
                let withdrawn = manager.applyRevocations(from: loaded)
                catalog = loaded
                notices = withdrawn.map { String(localized: "Turned off \($0.name): it was withdrawn from the catalog.", comment: "Settings → Extensions notice; the value is the extension name") }
                reload(); if !withdrawn.isEmpty { onChange() }
            case .failure(let failure): catalogError = failure.localizedDescription
            }
        }
    }
    private func checkForUpdates() { reload(); onChange(); loadCatalog() }
    /// Downloads and installs one listing, then reports a failure message, or nil on success. An update
    /// that asks for new access leaves the extension off, and says so.
    private func install(_ listing: ExtensionCatalog.Listing, from catalog: ExtensionCatalog, completion: @escaping (String?) -> Void = { _ in }) {
        installing = listing.id
        let wasEnabled = installed.first { $0.id == listing.id }?.enabled == true
        catalogClient.download(listing) { result in
            installing = nil
            do {
                let manager = manager
                guard manager.communityAllowed else { throw ExtensionManager.ExtensionError.communityDisabled }
                let files = try result.get()
                let updated = try manager.install(listing, manifest: files.manifest, module: files.module, icon: files.icon, from: catalog)
                if wasEnabled && !updated.enabled { notices.append(String(localized: "\(updated.name) \(updated.manifest.version) asks for new access, so it is off. Turn it on to review it.", comment: "Settings → Extensions notice; the values are the extension name and version")) }
                reload(); onChange(); completion(nil)
            } catch { reload(); completion(error.localizedDescription) }
        }
    }
    private func update(_ listing: ExtensionCatalog.Listing) {
        guard let catalog else { return }
        notices = []
        install(listing, from: catalog) { failure in if let failure { error = failure } }
    }
    /// Installs every available update one at a time, then shows any failures together.
    private func updateAll() {
        guard let catalog else { return }
        var queue = updates.map(\.listing)
        var failures: [String] = []
        updatingAll = true; notices = []
        func next() {
            guard !queue.isEmpty else {
                updatingAll = false
                if !failures.isEmpty { error = failures.joined(separator: "\n") }
                return
            }
            install(queue.removeFirst(), from: catalog) { failure in
                if let failure { failures.append(failure) }
                next()
            }
        }
        next()
    }
    /// Installed community extensions with a newer version in the loaded catalog.
    private var updates: [(ext: InstalledExtension, listing: ExtensionCatalog.Listing)] {
        guard let catalog else { return [] }
        return installed.compactMap { ext in
            guard let listing = catalog.installable.first(where: { $0.id == ext.id }),
                  case .update = ExtensionManager.catalogStatus(listing, installed: installed) else { return nil }
            return (ext, listing)
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
            if communityAllowed { updatesSection }
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
                        Button("Browse Extensions…") { browsing = true }.controlSize(.small).font(.callout)
                            .accessibilityIdentifier("extension-browse")
                    }
                }
            } footer: {
                SettingsFooter(String(localized: "Extensions start off and run only when you invoke them. An update keeps an extension on unless it asks for new access; other changed code needs enabling again. Turned-off extensions stay out of search; type ext and a name to find one. Uninstalling moves an extension to the Trash with its data and unused host access. Try Hello World: turn it on, then type hello Andrew", comment: "Footer in Settings → Extensions; ext and hello are typed launcher commands and stay in English"))
            }
            if communityAllowed || !approvedHosts.isEmpty { networkAccessSection }
            if communityAllowed || !locationSharing.isEmpty { locationSection }
        }
        .formStyle(.settings)
        .onAppear(perform: reload)
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)) { _ in reload() }
        .sheet(isPresented: $browsing) {
            ExtensionBrowseView(catalog: catalog, loading: catalogLoading, error: catalogError, installing: installing, installed: installed,
                                communityAllowed: communityAllowed, load: loadCatalog,
                                install: { listing in
                                    guard let catalog else { return }
                                    install(listing, from: catalog) { failure in if let failure { error = failure } }
                                },
                                done: { browsing = false })
        }
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
        let update = updates.first { $0.ext.id == ext.id }?.listing
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
                    Text(rowDetails(ext))
                }.disabled(ext.communityBlocked || (ext.revocation != nil && !ext.enabled)).accessibilityIdentifier("extension-toggle-" + ext.id)
            }
            if let revocation = ext.revocation {
                Label(revocation.reason.map { String(localized: "Withdrawn from the catalog: \($0)", comment: "Settings → Extensions row warning; the value is the catalog's reason") }
                      ?? String(localized: "Withdrawn from the catalog. Update or uninstall it.", comment: "Settings → Extensions row warning"),
                      systemImage: "exclamationmark.triangle.fill")
                    .font(.callout).foregroundStyle(.red).fixedSize(horizontal: false, vertical: true)
                    .padding(.leading, 34).accessibilityIdentifier("extension-revoked-" + ext.id)
            }
            if hasData || hasSecrets || ext.isCommunity {
                HStack(spacing: 8) {
                    if let update {
                        if installing == update.id {
                            ProgressView().controlSize(.small)
                        } else {
                            Button("Update to \(update.version)") { self.update(update) }.controlSize(.small)
                                .disabled(installing != nil || updatingAll || ext.communityBlocked)
                                .accessibilityIdentifier("extension-update-" + ext.id)
                        }
                    }
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

    /// The details under an extension's name: where it came from, its version, its access and whether
    /// it still needs host approval, separated by middle dots.
    private func rowDetails(_ ext: InstalledExtension) -> String {
        let origin = ext.isCommunity
            ? (ext.communityBlocked ? String(localized: "Community · Blocked by master switch", comment: "Settings → Extensions row detail")
                : String(localized: "Community", comment: "Settings → Extensions row detail: a community extension"))
            : String(localized: "Bundled with Volant", comment: "Settings → Extensions row detail")
        var parts = [origin]
        if ext.catalogOrigin != nil { parts.append(String(localized: "From catalog", comment: "Settings → Extensions row detail")) }
        parts.append(String(localized: "Version \(ext.manifest.version)", comment: "Settings → Extensions row detail; the value is a version number"))
        parts.append(ext.accessDescription)
        if ext.enabled && !ExtensionHostApprovals.missing(ext.manifest, at: configURL).isEmpty {
            parts.append(String(localized: "Asks for host access on next use", comment: "Settings → Extensions row detail"))
        }
        return parts.joined(separator: " · ")
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
                        CommunityPoint(symbol: "shield.lefthalf.filled", title: String(localized: "Sandboxed", comment: "Community extensions safety point title"),
                                       text: String(localized: "Each runs as WebAssembly in a separate sandboxed helper, with no access to your files or the network."))
                        CommunityPoint(symbol: "checkmark.seal", title: String(localized: "Reviewed and signed", comment: "Community extensions safety point title"),
                                       text: String(localized: "Catalog extensions are reviewed for Volant, and every download is checked against the signed catalog."))
                    }
                    GridRow {
                        CommunityPoint(symbol: "hand.raised", title: String(localized: "You approve access", comment: "Community extensions safety point title"),
                                       text: String(localized: "Volant fetches only from sites you allow for each extension. Location needs its own approval."))
                        CommunityPoint(symbol: "chevron.left.forwardslash.chevron.right", title: String(localized: "Source you can read", comment: "Community extensions safety point title"),
                                       text: String(localized: "Every catalog listing links to the exact source it was built from."))
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
                     ? String(localized: "You choose which ones to install and turn on.", comment: "Settings → Extensions, Allow community extensions detail")
                     : String(localized: "Your \(blockedCommunityCount) installed community extensions come back as you left them.", comment: "Settings → Extensions, Allow community extensions detail; the value is a count"))
            }
        } footer: {
            Link("Learn more about extension security", destination: URL(string: "https://usevolant.com/docs/privacy-and-security")!)
                .font(.callout)
        }
    }

    /// Whether installed catalog extensions are current: check the signed catalog, then update one or all.
    @ViewBuilder private var updatesSection: some View {
        Section {
            LabeledContent {
                if catalogLoading || updatingAll {
                    ProgressView().controlSize(.small)
                } else if !updates.isEmpty {
                    Button("Update All") { updateAll() }.buttonStyle(.borderedProminent)
                        .disabled(installing != nil).accessibilityIdentifier("extension-update-all")
                } else {
                    Button("Check for Updates") { checkForUpdates() }
                        .disabled(installing != nil).accessibilityIdentifier("extension-refresh")
                }
            } label: {
                Text(updatesTitle)
                Text(updatesDetail)
            }
            ForEach(notices, id: \.self) { Text($0).font(.callout).foregroundStyle(.secondary) }
        }
    }

    private var updatesTitle: String {
        if updatingAll { return String(localized: "Updating extensions…", comment: "Settings → Extensions updates status") }
        if catalogLoading { return String(localized: "Checking the catalog…", comment: "Settings → Extensions updates status") }
        if catalogError != nil { return String(localized: "Couldn’t check for updates", comment: "Settings → Extensions updates status") }
        guard catalog != nil else { return String(localized: "Updates", comment: "Settings → Extensions updates row title before checking") }
        let count = updates.count
        if count > 0 { return String(localized: "\(count) updates available", comment: "Settings → Extensions updates status; the value is a count") }
        let withdrawn = installed.filter { $0.revocation != nil }.count
        return withdrawn == 0 ? String(localized: "Your extensions are up to date", comment: "Settings → Extensions updates status")
            : String(localized: "\(withdrawn) extensions were withdrawn", comment: "Settings → Extensions updates status; the value is a count")
    }

    private var updatesDetail: String {
        if let catalogError, !catalogLoading { return catalogError }
        guard catalog != nil else { return String(localized: "Volant checks the signed catalog only when you ask.", comment: "Settings → Extensions updates detail") }
        let names = updates.map { "\($0.ext.name) \($0.listing.version)" }
        if !names.isEmpty { return names.joined(separator: ", ") }
        return installed.contains { $0.revocation != nil } ? String(localized: "Uninstall below, or update when a fixed version is listed.", comment: "Settings → Extensions updates detail")
            : String(localized: "Checked the signed catalog.", comment: "Settings → Extensions updates detail")
    }

    @ViewBuilder private var networkAccessSection: some View {
            Section {
                if approvedHosts.isEmpty { Text("No hosts allowed.").foregroundStyle(.secondary) }
                ForEach(approvedHosts, id: \.self) { host in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(host).font(.body.monospaced())
                            let names = users(of: host)
                            Text(names.isEmpty ? String(localized: "Not used by any installed extension", comment: "Settings → Extensions network host detail")
                                 : String(localized: "Used by \(names.joined(separator: ", "))", comment: "Settings → Extensions network host detail; the value lists extension names"))
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
                SettingsFooter(String(localized: "Volant fetches from these hosts for network extensions, which have no network access themselves. Removing a host stops every extension that uses it until you allow it again.", comment: "Footer in Settings → Extensions"))
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
                            Text(String(localized: "Approximate location, about 11 km, shared with \(ext.manifest.declaredHosts.joined(separator: ", "))", comment: "Settings → Extensions location detail; the value lists web hosts"))
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
                SettingsFooter(String(localized: "Each extension here was allowed your location separately. Volant asks macOS for it only when the extension runs, rounds it to about 11 km, and never saves it. Stopping makes the extension ask again on its next run.", comment: "Footer in Settings → Extensions"))
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
            Text(secret.help.map { String(localized: "\($0) Volant keeps it in your Keychain and adds it only to requests to \(secret.host). The extension never sees it.", comment: "Extension token field note; the values are the extension's own help text and a web host") }
                 ?? String(localized: "Volant keeps it in your Keychain and adds it only to requests to \(secret.host). The extension never sees it.", comment: "Extension token field note; the value is a web host"))
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
