import SwiftUI
import VolantCore

/// Reloads whenever a window becomes key as well as on appear, so enabling an extension or allowing
/// hosts from the launcher shows here when Settings comes back, even if this pane never left the screen.
/// The catalog is fetched only when the owner chooses Check Catalog; fixtures pass `catalog` to start loaded.
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
    init(configURL: URL, onChange: @escaping () -> Void, roots: [URL]? = nil, directory: URL? = nil, dataDirectory: URL? = nil,
         catalogClient: ExtensionCatalogClient = .live, catalog: ExtensionCatalog? = nil) {
        self.configURL = configURL; self.onChange = onChange; self.roots = roots; self.directory = directory; self.dataDirectory = dataDirectory
        self.catalogClient = catalogClient
        _catalog = State(initialValue: catalog)
    }
    private var manager: ExtensionManager { ExtensionManager(configURL: configURL, roots: roots, directory: directory, dataDirectory: dataDirectory) }
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
            Section {
                Toggle("Allow Community Extensions", isOn: Binding(get: { communityAllowed }, set: { allowed in
                    do { try manager.setCommunityAllowed(allowed, expected: communityAllowed); reload(); onChange() }
                    catch { self.error = error.localizedDescription; reload() }
                })).accessibilityIdentifier("community-extensions-toggle")
            } footer: {
                SettingsFooter("Off blocks community commands and discards results from active runs. Your individual choices are kept. Bundled extensions are controlled separately below.")
            }
            Section {
                if installed.isEmpty { Text("No extensions installed.").foregroundStyle(.secondary) }
                ForEach(installed) { ext in
                    HStack {
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
                        if ext.manifest.usesStorage && manager.hasStoredData(ext) {
                            Button("Clear Data…") { confirmingClear = ext }.controlSize(.small)
                                .accessibilityIdentifier("extension-clear-data-" + ext.id)
                        }
                        if ext.isCommunity {
                            Button("Uninstall…") { confirmingUninstall = ext }.controlSize(.small)
                                .accessibilityIdentifier("extension-uninstall-" + ext.id)
                        }
                    }
                }
                ForEach(problems, id: \.self) { Text($0).foregroundStyle(.secondary) }
            } header: {
                HStack {
                    Text("Installed")
                    Spacer()
                    Button("Open Folder") { NSWorkspace.shared.open(ExtensionManager.directory) }.controlSize(.small).font(.callout)
                    Button("Refresh") { reload(); onChange(); if catalog != nil { loadCatalog() } }.controlSize(.small).font(.callout)
                        .disabled(catalogLoading || installing != nil)
                }
            } footer: {
                SettingsFooter("Uninstalling moves a community extension to the Trash, deletes what it saved and removes host access no other extension uses. Extensions start off and run only when you invoke them. Enable one here or choose Enable and Run the first time you use it; changed code or permissions require enabling again. Try the bundled example: hello Andrew")
            }
            Section {
                if let catalog {
                    if catalog.extensions.isEmpty { Text("The catalog has no extensions yet.").foregroundStyle(.secondary) }
                    // Installed rows already use extension IDs; sharing them in one Form misplaces rows.
                    ForEach(catalog.extensions, id: \.catalogRowID) { listing in catalogRow(listing, from: catalog) }
                } else if catalogLoading {
                    HStack(spacing: 8) { ProgressView().controlSize(.small); Text("Checking the catalog…").foregroundStyle(.secondary) }
                } else {
                    HStack {
                        Text(catalogError ?? "Volant contacts the catalog only when you check it.").foregroundStyle(.secondary)
                        Spacer()
                        Button("Check Catalog") { loadCatalog() }.controlSize(.small)
                            .accessibilityIdentifier("extension-catalog-check")
                    }
                }
            } header: {
                Text("Catalog")
            } footer: {
                SettingsFooter((communityAllowed ? "" : "Turn on Allow Community Extensions to install from the catalog. ")
                    + "Extensions here are reviewed and signed for Volant. Refresh above checks the catalog again. You can also browse it from the launcher: type catalog. Each download is checked against the signed catalog before it is installed. Installing never turns an extension on or runs it; first use asks as usual, and an update with changed code or permissions needs enabling again.")
            }
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
                SettingsFooter("Hosts you allowed network extensions to read. Volant fetches from them for the extension; the extension itself has no network access. Removing a host stops every extension that uses it until you allow it again.")
            }
        }
        .formStyle(.grouped)
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
}

struct ExtensionPermissionView: View {
    let request: ExtensionPermissionRequest
    let enable: () -> Void
    let cancel: () -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(request.extensionItem.enabled ? "Allow \(request.extensionItem.name) to go online?" : "Enable \(request.extensionItem.name)?")
                .font(.title2.bold())
            if request.hosts.isEmpty {
                Text(request.extensionItem.accessDescription)
            } else {
                ExtensionHostList(hosts: request.hosts)
            }
            Text("This extension will run now and stay enabled. You can turn it off, or remove its hosts, in Settings → Extensions.")
                .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            HStack {
                Spacer()
                Button("Cancel", action: cancel).keyboardShortcut(.cancelAction)
                Button(request.hosts.isEmpty ? "Enable and Run" : "Allow and Run", action: enable).keyboardShortcut(.defaultAction)
            }
        }.padding(24).frame(width: 390)
            .background(Color(nsColor: .windowBackgroundColor))
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
