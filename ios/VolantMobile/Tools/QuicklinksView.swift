import SwiftUI
import VolantCore

/// The quicklinks shared with the Mac. Tapping opens one (asking for the text when it has a
/// `{query}` slot); holding offers Edit, Copy Link and Delete; + adds one. Every URL goes through
/// VolantCore's scheme check, so only web, mail and Shortcuts run links open or save.
struct QuicklinksView: View {
    @EnvironmentObject private var mac: MacSettings
    @Environment(\.volantTheme) private var theme
    @State private var query = ""
    @State private var asking: Quicklink?
    @State private var editing: EditTarget?
    @State private var toast: String?

    /// The quicklink being edited, by position, or a new one.
    struct EditTarget: Identifiable {
        let index: Int?
        var id: Int { index ?? -1 }
    }

    private var filtered: [(index: Int, link: Quicklink)] {
        let all = Array(mac.quicklinks.enumerated()).map { (index: $0.offset, link: $0.element) }
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return all }
        return all.filter { $0.link.name.localizedCaseInsensitiveContains(q) || $0.link.url.localizedCaseInsensitiveContains(q) }
    }

    var body: some View {
        List {
            ForEach(filtered, id: \.index) { item in
                QuicklinkButton(link: item.link, asking: $asking)
                    .listRowBackground(theme.hasPalette ? theme.raisedSurface : nil)
                    .swipeActions(edge: .trailing) {
                        Button(role: .destructive) { mac.deleteQuicklink(at: item.index) } label: { Label("Delete", systemImage: "trash") }
                        Button { editing = EditTarget(index: item.index) } label: { Label("Edit", systemImage: "pencil") }
                            .tint(Tool.quicklinks.colors[1])
                    }
                    .contextMenu {
                        Button("Edit", systemImage: "pencil") { editing = EditTarget(index: item.index) }
                            .disabled(!mac.canEdit)
                        Button("Copy Link", systemImage: "link") {
                            UIPasteboard.general.string = item.link.url
                            toast = String(localized: "Copied link")
                        }
                        Divider()
                        Button("Delete", systemImage: "trash", role: .destructive) { mac.deleteQuicklink(at: item.index) }
                    }
            }
        }
        .overlay { MacSyncEmptyState(tool: .quicklinks, isEmpty: mac.quicklinks.isEmpty, filterEmpty: filtered.isEmpty, query: query) }
        .scrollContentBackground(theme.hasPalette ? .hidden : .automatic)
        .background(theme.hasPalette ? theme.background : nil)
        .navigationTitle("Quicklinks")
        .searchable(text: $query, prompt: "Search Quicklinks")
        .refreshable { mac.refresh() }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { editing = EditTarget(index: nil) } label: { Image(systemName: "plus") }
                    .accessibilityLabel("New Quicklink")
                    .disabled(!mac.canEdit)
            }
        }
        .sheet(item: $asking) { QuicklinkQuerySheet(link: $0) }
        .sheet(item: $editing) { QuicklinkEditor(index: $0.index) }
        .toast($toast)
    }
}

extension Quicklink: @retroactive Identifiable {
    public var id: String { name + "\u{0}" + url }

    var takesQuery: Bool { url.contains("{query}") }

    /// The host shown under a link's name, or the raw template when it has none.
    var displayHost: String {
        URL(string: url.replacingOccurrences(of: "{query}", with: "q"))?.host() ?? url
    }

    /// Whether VolantCore would open this link, checked with sample search text for `{query}` links.
    var isOpenable: Bool { resolvedURL(query: "volant") != nil }
}

/// One quicklink row: opens at once, or asks for the query.
struct QuicklinkButton: View {
    let link: Quicklink
    @Binding var asking: Quicklink?
    @Environment(\.openURL) private var openURL

    var body: some View {
        Button {
            if link.takesQuery { asking = link } else if let url = link.resolvedURL(query: "") { openURL(url) }
        } label: {
            HStack(spacing: 12) {
                ToolIcon(tool: .quicklinks, size: 30)
                VStack(alignment: .leading, spacing: 2) {
                    Text(link.name).font(.headline)
                    Text(link.displayHost).font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer()
                Image(systemName: link.takesQuery ? "magnifyingglass" : "arrow.up.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
        }
        .buttonStyle(.row)
        .disabled(!link.takesQuery && link.resolvedURL(query: "") == nil)
    }
}

/// Adds or edits a quicklink: a name and a URL, where `{query}` marks where search text goes.
struct QuicklinkEditor: View {
    let index: Int?
    @EnvironmentObject private var mac: MacSettings
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var url = ""
    @State private var loaded = false

    private var draft: Quicklink { Quicklink(name: name.trimmingCharacters(in: .whitespaces), url: url.trimmingCharacters(in: .whitespaces)) }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Name", text: $name)
                    TextField("URL", text: $url, axis: .vertical)
                        .font(.body.monospaced())
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    Button("Insert {query}", systemImage: "magnifyingglass") { url += "{query}" }
                        .disabled(url.contains("{query}"))
                } footer: {
                    if !url.isEmpty && !draft.isOpenable {
                        Text("Use a web (https), mail or Shortcuts run link.").foregroundStyle(.red)
                    } else {
                        Text("Put {query} where search text goes, as in https://www.google.com/search?q={query}.")
                    }
                }
            }
            .navigationTitle(index == nil ? "New Quicklink" : "Edit Quicklink")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        mac.save(draft, at: index)
                        dismiss()
                    }
                    .disabled(draft.name.isEmpty || !draft.isOpenable)
                }
            }
            .onAppear {
                guard !loaded else { return }
                loaded = true
                if let index, let link = mac.quicklinks[safe: index] {
                    name = link.name
                    url = link.url
                }
            }
        }
    }
}

/// Asks for the text a `{query}` quicklink searches for, then opens it.
struct QuicklinkQuerySheet: View {
    let link: Quicklink
    @State private var text = ""
    @FocusState private var focused: Bool
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 12) {
                    ToolIcon(tool: .quicklinks, size: 40)
                    VStack(alignment: .leading) {
                        Text(link.name).font(.title3.weight(.semibold))
                        Text(link.displayHost).font(.subheadline).foregroundStyle(.secondary)
                    }
                }
                TextField("Search \(link.name)", text: $text)
                    .textFieldStyle(.roundedBorder)
                    .font(.title3)
                    .focused($focused)
                    .submitLabel(.go)
                    .onSubmit(open)
                Spacer()
            }
            .padding(20)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Open", action: open).disabled(text.isEmpty) }
            }
            .onAppear { focused = true }
        }
        .presentationDetents([.height(220)])
    }

    private func open() {
        guard !text.isEmpty, let url = link.resolvedURL(query: text) else { return }
        dismiss()
        openURL(url)
    }
}
