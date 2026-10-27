import SwiftUI
import VolantCore

/// The launcher's Extension Catalog: search on top, the matching extensions on the left and the
/// selected one's details on the right. Arrow keys move the selection from the search field,
/// Return installs, updates or uses it, and Command-Return opens its source.
struct ExtensionCatalogView: View {
    @ObservedObject var model: ExtensionCatalogModel
    let caffeinate: CaffeinateService
    let back: () -> Void
    @FocusState private var editing: Bool
    @Environment(\.volantTheme) private var theme

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 14) {
                Button(action: back) { Image(systemName: "chevron.left") }
                    .buttonStyle(.plain).accessibilityLabel("Back to search")
                    .keyboardShortcut("[", modifiers: .command).help("Back to search (⌘[)")
                TextField("Search extensions…", text: $model.input)
                    .textFieldStyle(.plain).font(.system(size: 22)).focused($editing)
                    .accessibilityLabel("Search the extension catalog")
                    .onKeyPress(.return, phases: .down) { press in
                        if press.modifiers.contains(.command) { model.openSource() } else { model.performPrimary() }
                        return .handled
                    }
                    .onKeyPress(.downArrow) { model.moveSelection(1); return .handled }
                    .onKeyPress(.upArrow) { model.moveSelection(-1); return .handled }
                if !model.input.isEmpty {
                    Button { model.input = ""; editing = true } label: { Image(systemName: "xmark.circle.fill") }
                        .buttonStyle(.plain).foregroundStyle(.secondary).accessibilityLabel("Clear catalog search")
                }
            }.padding(16)
            Divider()
            content.frame(maxWidth: .infinity, maxHeight: .infinity)
            if let message = model.feedback {
                Text(message).font(.caption).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 16).padding(.bottom, 8)
                    .accessibilityIdentifier("catalog-feedback")
            }
            Divider()
            HStack(spacing: 12) {
                Image("VolantWing").renderingMode(.template).resizable().scaledToFit()
                    .frame(width: 16, height: 16).foregroundStyle(.tint).overlay(LauncherDragHandle())
                    .help("Drag to position Volant")
                CaffeinateStatusView(service: caffeinate)
                Text("Extension Catalog").font(.system(size: 13, weight: .medium))
                Spacer(minLength: 0)
                if model.selected?.sourceURL != nil {
                    Button("View Source ⌘↩") { model.openSource() }
                }
                if !model.primaryTitle.isEmpty {
                    Button(model.primaryTitle + " ↩") { model.performPrimary() }
                        .buttonStyle(.borderedProminent)
                        .disabled(model.loading || model.installing != nil)
                        .accessibilityIdentifier("catalog-primary")
                }
            }.controlSize(.small).padding(.horizontal, 16).padding(.vertical, 10)
        }
        .onAppear { DispatchQueue.main.async { editing = true } }
        .onDisappear { model.leave() }
    }

    @ViewBuilder private var content: some View {
        if model.catalog == nil {
            VStack(alignment: .leading, spacing: 12) {
                Label("Extension Catalog", systemImage: "puzzlepiece.extension").font(.title3.weight(.semibold))
                Text("Browse extensions reviewed and signed for Volant. Volant contacts the catalog only when you check it.")
                    .foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                if model.loading {
                    HStack { ProgressView().controlSize(.small); Text("Checking the catalog…").foregroundStyle(.secondary) }
                } else {
                    if let error = model.error { Text(error).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true) }
                    Button(model.error == nil ? "Check Catalog" : "Try Again") { model.load() }
                        .accessibilityIdentifier("catalog-check")
                }
            }.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading).padding(20)
        } else if model.listings.isEmpty {
            Text(model.catalog?.extensions.isEmpty == true ? "The catalog has no extensions yet." : "No extensions match “\(model.input)”.")
                .foregroundStyle(.secondary).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading).padding(20)
        } else {
            HStack(spacing: 0) {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 2) {
                            ForEach(model.listings) { listing in row(listing).id(listing.id) }
                        }.padding(8)
                    }
                    .onChange(of: model.selectedID) { _, id in if let id { proxy.scrollTo(id) } }
                }
                .frame(width: 270)
                Divider()
                if let listing = model.selected {
                    ScrollView { detail(listing).padding(20) }.frame(maxWidth: .infinity)
                }
            }
        }
    }

    private func row(_ listing: ExtensionCatalog.Listing) -> some View {
        let selected = listing.id == model.selected?.id
        return Button { model.selectedID = listing.id; editing = true } label: {
            HStack(spacing: 10) {
                CatalogIcon(installed: model.installed(listing), size: 22)
                VStack(alignment: .leading, spacing: 1) {
                    Text(listing.name).lineLimit(1)
                    Text(statusText(listing)).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer(minLength: 0)
                if model.installing == listing.id { ProgressView().controlSize(.small) }
            }
            .padding(.horizontal, 8).padding(.vertical, 6)
            .contentShape(Rectangle())
            .background(selected ? theme.selection : AnyShapeStyle(Color.clear), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityIdentifier("catalog-row-" + listing.id)
    }

    private func statusText(_ listing: ExtensionCatalog.Listing) -> String {
        switch model.status(listing) {
        case .available: return String(localized: "Version \(listing.version)", comment: "Extension catalog row status; the value is a version number")
        case .update(let from): return String(localized: "Update: \(from) → \(listing.version)", comment: "Extension catalog row status; the values are the installed and new versions")
        case .installed: return model.installed(listing)?.enabled == true ? String(localized: "Installed · \(listing.version)", comment: "Extension catalog row status; the value is a version number")
            : String(localized: "Off · \(listing.version)", comment: "Extension catalog row status; the value is a version number")
        case .bundled: return String(localized: "Bundled with Volant", comment: "Extension catalog row status")
        }
    }

    @ViewBuilder private func detail(_ listing: ExtensionCatalog.Listing) -> some View {
        let installed = model.installed(listing)
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 14) {
                CatalogIcon(installed: installed, size: 48)
                VStack(alignment: .leading, spacing: 3) {
                    Text(listing.name).font(.title2.weight(.semibold))
                    Text("\(listing.publisher) · Version \(listing.version) · \(listing.license)").foregroundStyle(.secondary)
                }
            }
            Text(listing.summary).font(.system(size: 15)).fixedSize(horizontal: false, vertical: true)
            if let notes = listing.notes, !notes.isEmpty {
                Text(notes).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            section(String(localized: "Access", comment: "Extension catalog detail section heading")) {
                if listing.storage == true {
                    Label("Remember settings and lists on this Mac", systemImage: "internaldrive")
                }
                if listing.capabilities.isEmpty && listing.hosts.isEmpty && listing.storage != true {
                    Label("No permissions required", systemImage: "checkmark.shield").foregroundStyle(.secondary)
                }
                ForEach(listing.capabilities, id: \.self) { capability in
                    Label(InstalledExtension.accessDescription(capabilities: [capability], hosts: []), systemImage: "key")
                }
                ForEach(listing.hosts, id: \.self) { host in
                    Label(host, systemImage: "network").font(.body.monospaced())
                }
                if !listing.hosts.isEmpty {
                    Text("Volant fetches pages from these hosts for the extension, after you allow them. The extension itself has no network access.")
                        .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
            }
            section(String(localized: "On this Mac", comment: "Extension catalog detail section heading")) {
                Text(onThisMac(listing, installed: installed)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            if let source = listing.sourceURL {
                Button { model.openSource() } label: { Label("Source at the reviewed revision", systemImage: "chevron.left.forwardslash.chevron.right") }
                    .buttonStyle(.link).help(source.absoluteString)
            }
        }.frame(maxWidth: .infinity, alignment: .leading)
    }

    private func onThisMac(_ listing: ExtensionCatalog.Listing, installed: InstalledExtension?) -> String {
        switch model.status(listing) {
        case .available:
            return model.communityAllowed ? String(localized: "Not installed. Installing doesn’t turn it on; it asks the first time you use it.", comment: "Extension catalog detail, On this Mac section")
                : String(localized: "Not installed. Turn on Allow Community Extensions in Settings to install it.", comment: "Extension catalog detail, On this Mac section")
        case .update(let from):
            return String(localized: "Version \(from) is installed. Updating replaces it in one step; changed code, permissions or hosts need enabling again.", comment: "Extension catalog detail, On this Mac section; the value is the installed version")
        case .installed:
            return installed?.enabled == true ? String(localized: "Installed and on. Type \(listing.name) in the launcher.", comment: "Extension catalog detail, On this Mac section; the value is the extension name")
                : String(localized: "Installed and off, so it doesn’t appear in search. Choose Turn On to allow it; it asks for any hosts first.", comment: "Extension catalog detail, On this Mac section")
        case .bundled:
            return String(localized: "Bundled with Volant.", comment: "Extension catalog detail, On this Mac section")
        }
    }

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.headline)
            content()
        }
    }
}

/// An installed extension's own icon, or the catalog symbol.
private struct CatalogIcon: View {
    let installed: InstalledExtension?
    let size: CGFloat

    var body: some View {
        Group {
            if let installed, let icon = ExtensionIcon.image(for: installed) {
                Image(nsImage: icon).resizable()
            } else {
                RoundedRectangle(cornerRadius: size / 4, style: .continuous)
                    .fill(Color(red: 0.95, green: 0.42, blue: 0.29).gradient)
                    .overlay {
                        Image(systemName: "puzzlepiece.extension").symbolVariant(.fill)
                            .font(.system(size: size * 0.5, weight: .semibold)).foregroundStyle(.white)
                    }
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: size / 4, style: .continuous))
        .accessibilityHidden(true)
    }
}
