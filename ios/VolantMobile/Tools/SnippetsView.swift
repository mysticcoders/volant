import SwiftUI
import VolantCore

/// The snippets shared with the Mac. Tapping one opens it to copy or edit; swiping copies or
/// deletes; the + button adds one. Changes reach the Mac through settings sync.
struct SnippetsView: View {
    @EnvironmentObject private var mac: MacSettings
    @Environment(\.volantTheme) private var theme
    @State private var query = ""
    @State private var toast: String?
    @State private var adding = false

    private var filtered: [(index: Int, snippet: Snippet)] {
        let all = Array(mac.snippets.enumerated()).map { (index: $0.offset, snippet: $0.element) }
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return all }
        return all.filter { $0.snippet.name.localizedCaseInsensitiveContains(q) || $0.snippet.keyword.localizedCaseInsensitiveContains(q) || $0.snippet.body.localizedCaseInsensitiveContains(q) }
    }

    var body: some View {
        List {
            ForEach(filtered, id: \.index) { item in
                NavigationLink {
                    SnippetDetailView(index: item.index)
                } label: {
                    SnippetRow(snippet: item.snippet)
                }
                .listRowBackground(theme.hasPalette ? theme.raisedSurface : nil)
                .swipeActions(edge: .leading) {
                    Button { copy(item.snippet) } label: { Label("Copy", systemImage: "doc.on.doc") }
                        .tint(Tool.snippets.colors[1])
                }
                .swipeActions(edge: .trailing) {
                    Button(role: .destructive) { mac.deleteSnippet(at: item.index) } label: { Label("Delete", systemImage: "trash") }
                }
                .contextMenu {
                    Button("Copy", systemImage: "doc.on.doc") { copy(item.snippet) }
                    ShareLink(item: MacSettings.expand(item.snippet.body)) { Label("Share", systemImage: "square.and.arrow.up") }
                    Divider()
                    Button("Delete", systemImage: "trash", role: .destructive) { mac.deleteSnippet(at: item.index) }
                }
            }
        }
        .overlay { MacSyncEmptyState(tool: .snippets, isEmpty: mac.snippets.isEmpty, filterEmpty: filtered.isEmpty, query: query) }
        .scrollContentBackground(theme.hasPalette ? .hidden : .automatic)
        .background(theme.hasPalette ? theme.background : nil)
        .navigationTitle("Snippets")
        .searchable(text: $query, prompt: "Search Snippets")
        .refreshable { mac.refresh() }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { adding = true } label: { Image(systemName: "plus") }
                    .accessibilityLabel("New Snippet")
                    .disabled(!mac.canEdit)
            }
        }
        .sheet(isPresented: $adding) { SnippetEditor(index: nil) }
        .toast($toast)
    }

    private func copy(_ snippet: Snippet) {
        UIPasteboard.general.string = MacSettings.expand(snippet.body)
        toast = String(localized: "Copied \(snippet.name)")
    }
}

/// One snippet: its name and keyword, the text as it will be copied, and Copy and Edit.
struct SnippetDetailView: View {
    let index: Int
    @EnvironmentObject private var mac: MacSettings
    @Environment(\.volantTheme) private var theme
    @State private var editing = false
    @State private var toast: String?

    var body: some View {
        if let snippet = mac.snippets[safe: index] {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    HStack(spacing: 14) {
                        ToolIcon(tool: .snippets, size: 48)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(snippet.name).font(.title2.weight(.bold))
                            if !snippet.keyword.isEmpty {
                                Text(snippet.keyword).font(.subheadline.monospaced()).foregroundStyle(.secondary)
                            }
                        }
                    }
                    Text(MacSettings.expand(snippet.body))
                        .font(.body)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(16)
                        .background(theme.raisedSurface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    Button {
                        UIPasteboard.general.string = MacSettings.expand(snippet.body)
                        toast = String(localized: "Copied \(snippet.name)")
                    } label: {
                        Label("Copy", systemImage: "doc.on.doc").frame(maxWidth: .infinity, minHeight: 34)
                    }
                    .buttonStyle(.borderedProminent)
                    .buttonBorderShape(.capsule)
                    if snippet.body.contains("{") {
                        Text("Placeholders such as {date} and {clipboard} are filled in when you copy, as on the Mac.")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                }
                .padding(20)
            }
            .background(theme.background)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Edit") { editing = true }.disabled(!mac.canEdit)
                }
            }
            .sheet(isPresented: $editing) { SnippetEditor(index: index) }
            .toast($toast)
        } else {
            ContentUnavailableView("Snippet Removed", systemImage: "text.quote")
        }
    }
}

/// Adds or edits a snippet: name, keyword and text, with buttons that insert the Mac's placeholders.
struct SnippetEditor: View {
    let index: Int?
    @EnvironmentObject private var mac: MacSettings
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var keyword = ""
    @State private var text = ""
    @State private var loaded = false

    private static let placeholders = ["{date}", "{time}", "{datetime}", "{isodate}", "{clipboard}", "{uuid}"]

    private var duplicateKeyword: Bool {
        let k = keyword.trimmingCharacters(in: .whitespaces)
        return !k.isEmpty && mac.snippets.enumerated().contains { $0.offset != index && $0.element.keyword == k }
    }

    private var valid: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty && !text.isEmpty && !duplicateKeyword
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Name", text: $name)
                    TextField("Keyword", text: $keyword)
                        .font(.body.monospaced())
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                } footer: {
                    if duplicateKeyword {
                        Text("Another snippet already uses this keyword.").foregroundStyle(.red)
                    } else {
                        Text("On the Mac, typing the keyword expands the snippet.")
                    }
                }
                Section("Text") {
                    TextEditor(text: $text).frame(minHeight: 160)
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack {
                            ForEach(Self.placeholders, id: \.self) { token in
                                Button(token) { text += token }
                                    .font(.caption.monospaced())
                                    .buttonStyle(.bordered)
                                    .buttonBorderShape(.capsule)
                            }
                        }
                    }
                }
            }
            .navigationTitle(index == nil ? "New Snippet" : "Edit Snippet")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        mac.save(Snippet(name: name.trimmingCharacters(in: .whitespaces), keyword: keyword.trimmingCharacters(in: .whitespaces), body: text), at: index)
                        dismiss()
                    }
                    .disabled(!valid)
                }
            }
            .onAppear {
                guard !loaded else { return }
                loaded = true
                if let index, let snippet = mac.snippets[safe: index] {
                    name = snippet.name
                    keyword = snippet.keyword
                    text = snippet.body
                }
            }
        }
    }
}

struct SnippetRow: View {
    let snippet: Snippet

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            ToolIcon(tool: .snippets, size: 30)
            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    Text(snippet.name).font(.headline).foregroundStyle(Color.primary)
                    Spacer()
                    if !snippet.keyword.isEmpty {
                        Text(snippet.keyword)
                            .font(.caption.monospaced())
                            .foregroundStyle(Color.secondary)
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(.quaternary, in: .capsule)
                    }
                }
                Text(snippet.body).font(.subheadline).foregroundStyle(Color.secondary).lineLimit(2)
            }
        }
        .padding(.vertical, 2)
    }
}

/// What a tool shows when the Mac has shared nothing yet, or when a search finds nothing.
struct MacSyncEmptyState: View {
    @EnvironmentObject private var mac: MacSettings
    let tool: Tool
    let isEmpty: Bool
    let filterEmpty: Bool
    let query: String

    var body: some View {
        if isEmpty {
            switch mac.state {
            case .loading:
                ProgressView()
            case .unavailable:
                ContentUnavailableView("iCloud Is Off", systemImage: "icloud.slash",
                                       description: Text("Sign in to iCloud on this iPhone to see \(tool.title.lowercased()) from your Mac."))
            case .empty, .ready:
                ContentUnavailableView {
                    Label { Text("No \(tool.title) Yet") } icon: { ToolIcon(tool: tool, size: 56) }
                } description: {
                    Text("Tap + to add one. To share them with your Mac, turn on Volant › Settings › Data & Configuration › Sync settings and notes with iCloud there.")
                }
            }
        } else if filterEmpty {
            ContentUnavailableView.search(text: query)
        }
    }
}

extension Array {
    subscript(safe index: Int) -> Element? { indices.contains(index) ? self[index] : nil }
}
