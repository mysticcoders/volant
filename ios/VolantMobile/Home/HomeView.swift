import SwiftUI

/// The first tab: Volant's wordmark, quick actions, recent and pinned notes, and the privacy line.
struct HomeView: View {
    @EnvironmentObject private var model: NotesModel
    @EnvironmentObject private var router: AppRouter
    @Environment(\.volantTheme) private var theme

    private var recent: [Note] { Array(model.store.notes.filter { $0.readError == nil }.prefix(8)) }
    private var pinned: [Note] { model.store.notes.filter { model.pinned.contains($0.id) } }

    var body: some View {
        NavigationStack(path: $router.toolPath) {
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    header
                    actions
                    if !recent.isEmpty {
                        section("Recent") {
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 12) {
                                    ForEach(recent) { note in
                                        Button { router.open(noteID: note.id, in: model) } label: { NoteCard(note: note) }
                                            .buttonStyle(.plain)
                                    }
                                }
                                .padding(.horizontal, 20)
                            }
                            .scrollClipDisabled()
                        }
                    }
                    if !pinned.isEmpty {
                        section("Pinned") {
                            VStack(spacing: 0) {
                                ForEach(pinned) { note in
                                    Button { router.open(noteID: note.id, in: model) } label: { PinnedRow(note: note) }
                                        .buttonStyle(.plain)
                                    if note.id != pinned.last?.id { Divider().padding(.leading, 52) }
                                }
                            }
                            .background(theme.raisedSurface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                            .padding(.horizontal, 20)
                        }
                    }
                    footer
                }
                .padding(.vertical, 12)
            }
            .background(theme.background)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) { SettingsButton() }
            }
            .navigationDestination(for: Tool.self) { ToolDestination(tool: $0) }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            VolantWordmark(size: 30)
            Text(greeting).font(.title3).foregroundStyle(.secondary)
        }
        .padding(.horizontal, 20)
    }

    private var greeting: String {
        switch Calendar.current.component(.hour, from: Date()) {
        case 5..<12: String(localized: "Good morning")
        case 12..<17: String(localized: "Good afternoon")
        default: String(localized: "Good evening")
        }
    }

    private var actions: some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
            Button { router.newNote(in: model) } label: { ActionTile(tool: .notes, title: String(localized: "New Note")) }
                .buttonStyle(.plain)
            ForEach([Tool.snippets, .quicklinks, .calculator]) { tool in
                NavigationLink(value: tool) { ActionTile(tool: tool, title: tool.title) }
                    .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 20)
    }

    private func section<Content: View>(_ title: LocalizedStringKey, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title).font(.title3.weight(.semibold)).padding(.horizontal, 20)
            content()
        }
    }

    private var footer: some View {
        HStack(spacing: 8) {
            VolantMark(size: 14)
            Text(Brand.privacyLine)
        }
        .font(.footnote)
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity)
        .padding(.top, 8)
    }
}

/// A quick action: the tool's icon tile over its name, on a raised card.
struct ActionTile: View {
    let tool: Tool
    let title: String
    @Environment(\.volantTheme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            ToolIcon(tool: tool, size: 34)
            Text(title).font(.headline).foregroundStyle(.primary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(theme.raisedSurface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

/// A recent note as a small page: its title, the first lines, and when it changed.
struct NoteCard: View {
    let note: Note
    @Environment(\.volantTheme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(note.title).font(.headline).lineLimit(2).foregroundStyle(.primary)
            Text(NoteRow.plain(note.preview))
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(3)
            Spacer(minLength: 0)
            Text(note.modified, format: .relative(presentation: .named))
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .frame(width: 160, height: 150, alignment: .topLeading)
        .padding(14)
        .background(theme.raisedSurface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(alignment: .topTrailing) {
            Rectangle().fill(Brand.gradient).frame(width: 18, height: 3).clipShape(.capsule).padding(14)
        }
    }
}

struct PinnedRow: View {
    let note: Note

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "pin.fill").font(.footnote).foregroundStyle(.tint).frame(width: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(note.title).font(.body.weight(.medium)).lineLimit(1).foregroundStyle(.primary)
                Text(note.modified, format: .relative(presentation: .named)).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 12)
        .contentShape(.rect)
    }
}
