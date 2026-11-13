import SwiftUI

/// Every tool as a large card, two to a row.
struct MoreView: View {
    @EnvironmentObject private var model: NotesModel
    @EnvironmentObject private var router: AppRouter
    @EnvironmentObject private var mac: MacSettings
    @Environment(\.volantTheme) private var theme

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 14), GridItem(.flexible(), spacing: 14)], spacing: 14) {
                    Button { router.tab = .notes } label: { ToolCard(tool: .notes, count: model.store.notes.count) }
                        .buttonStyle(.plain)
                    NavigationLink(value: Tool.snippets) { ToolCard(tool: .snippets, count: mac.snippets.count) }
                        .buttonStyle(.plain)
                    NavigationLink(value: Tool.quicklinks) { ToolCard(tool: .quicklinks, count: mac.quicklinks.count) }
                        .buttonStyle(.plain)
                    NavigationLink(value: Tool.calculator) { ToolCard(tool: .calculator, count: nil) }
                        .buttonStyle(.plain)
                }
                .padding(20)
            }
            .background(theme.background)
            .navigationTitle("More")
            .toolbar { ToolbarItem(placement: .topBarTrailing) { SettingsButton() } }
            .navigationDestination(for: Tool.self) { ToolDestination(tool: $0) }
        }
    }
}

/// A tool's card: icon, name and what it does, with a count when it has items.
struct ToolCard: View {
    let tool: Tool
    let count: Int?
    @Environment(\.volantTheme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top) {
                ToolIcon(tool: tool, size: 40)
                Spacer()
                if let count, count > 0 {
                    Text(count, format: .number)
                        .font(.caption.weight(.semibold).monospacedDigit())
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 8).padding(.vertical, 3)
                        .background(.quaternary, in: .capsule)
                }
            }
            Spacer(minLength: 18)
            Text(tool.title).font(.title3.weight(.semibold)).foregroundStyle(.primary)
            Text(tool.subtitle).font(.footnote).foregroundStyle(.secondary).lineLimit(2, reservesSpace: true)
        }
        .frame(maxWidth: .infinity, minHeight: 150, alignment: .leading)
        .padding(16)
        .background(theme.raisedSurface, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
    }
}
