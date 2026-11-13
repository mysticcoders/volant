import SwiftUI
import VolantCore

/// One search across everything, like the Mac launcher: a calculator answer first, then notes,
/// snippets, and quicklinks, where a `{query}` link searches the typed text directly.
struct SearchView: View {
    @EnvironmentObject private var model: NotesModel
    @EnvironmentObject private var router: AppRouter
    @EnvironmentObject private var mac: MacSettings
    @Environment(\.volantTheme) private var theme
    @Environment(\.openURL) private var openURL
    @State private var query = UserDefaults.standard.string(forKey: "fixtureQuery") ?? ""
    @State private var toast: String?
    @State private var asking: Quicklink?

    private var term: String { query.trimmingCharacters(in: .whitespaces) }

    var body: some View {
        NavigationStack {
            List {
                if term.isEmpty {
                    Section {
                        ForEach(Tool.allCases) { tool in
                            if tool == .notes {
                                Button { router.tab = .notes } label: { ToolListRow(tool: tool) }
                                    .buttonStyle(.row)
                            } else {
                                NavigationLink(value: tool) { ToolListRow(tool: tool) }
                            }
                        }
                    } header: {
                        Text("Search notes, snippets and quicklinks, or type a calculation")
                            .textCase(nil)
                    }
                } else {
                    results
                }
            }
            .scrollContentBackground(theme.hasPalette ? .hidden : .automatic)
            .background(theme.hasPalette ? theme.background : nil)
            .navigationTitle("Search")
            .searchable(text: $query, prompt: "Notes, snippets, links, 5 km in mi…")
            .navigationDestination(for: Tool.self) { ToolDestination(tool: $0) }
            .sheet(item: $asking) { QuicklinkQuerySheet(link: $0) }
            .toast($toast)
        }
    }

    @ViewBuilder
    private var results: some View {
        let answers = CalculationAnswer.answers(for: term)
        let notes = model.store.search(term, limit: 6)
        let snippets = mac.snippets.filter { $0.name.localizedCaseInsensitiveContains(term) || $0.keyword.localizedCaseInsensitiveContains(term) }.prefix(5)
        let links = mac.quicklinks.filter { $0.name.localizedCaseInsensitiveContains(term) }.prefix(5)
        let searchable = mac.quicklinks.filter(\.takesQuery).prefix(3)

        if let answer = answers.first {
            Section("Calculator") {
                Button {
                    UIPasteboard.general.string = answer.copyText
                    toast = String(localized: "Copied \(answer.copyText)")
                } label: {
                    HStack(spacing: 12) {
                        ToolIcon(tool: .calculator, size: 30)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(answer.result).font(.title3.weight(.semibold)).foregroundStyle(.primary)
                            Text(answer.input).font(.subheadline).foregroundStyle(.secondary)
                        }
                    }
                }
                .buttonStyle(.row)
            }
        }
        if !notes.isEmpty {
            Section("Notes") {
                ForEach(notes) { note in
                    Button { router.open(noteID: note.id, in: model) } label: {
                        HStack(spacing: 12) {
                            ToolIcon(tool: .notes, size: 30)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(note.title).font(.headline).foregroundStyle(.primary).lineLimit(1)
                                Text(NoteRow.plain(note.preview)).font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
                            }
                        }
                    }
                .buttonStyle(.row)
                }
            }
        }
        if !snippets.isEmpty {
            Section("Snippets") {
                ForEach(Array(snippets), id: \.self) { snippet in
                    Button {
                        UIPasteboard.general.string = MacSettings.expand(snippet.body)
                        toast = String(localized: "Copied \(snippet.name)")
                    } label: { SnippetRow(snippet: snippet) }
                .buttonStyle(.row)
                }
            }
        }
        if !links.isEmpty || !searchable.isEmpty {
            Section("Quicklinks") {
                ForEach(Array(links)) { link in QuicklinkButton(link: link, asking: $asking) }
                ForEach(Array(searchable)) { link in
                    if let url = link.resolvedURL(query: term) {
                        Button { openURL(url) } label: {
                            HStack(spacing: 12) {
                                ToolIcon(tool: .quicklinks, size: 30)
                                Text(link.name.lowercased().hasPrefix(String(localized: "search").lowercased()) ? "\(link.name) for “\(term)”" : "Search \(link.name) for “\(term)”").foregroundStyle(.primary).lineLimit(2)
                                Spacer()
                                Image(systemName: "arrow.up.right").font(.footnote.weight(.semibold)).foregroundStyle(.tertiary)
                            }
                        }
                .buttonStyle(.row)
                    }
                }
            }
        }
        if answers.isEmpty && notes.isEmpty && snippets.isEmpty && links.isEmpty && searchable.isEmpty {
            ContentUnavailableView.search(text: term)
        }
    }
}

struct ToolListRow: View {
    let tool: Tool

    var body: some View {
        HStack(spacing: 12) {
            ToolIcon(tool: tool, size: 30)
            VStack(alignment: .leading, spacing: 2) {
                Text(tool.title).font(.headline).foregroundStyle(.primary)
                Text(tool.subtitle).font(.subheadline).foregroundStyle(.secondary)
            }
        }
    }
}
