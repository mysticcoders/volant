import SwiftUI

struct EmojiGridView: View {
    @ObservedObject var model: LauncherModel
    var body: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: LauncherModel.emojiColumns), spacing: 6) {
                        ForEach(model.rows) { row in
                            if case .emoji(let emoji) = row {
                                EmojiCell(emoji: emoji, rowID: row.id, model: model)
                            }
                        }
                    }.padding(16)
                    if model.rows.isEmpty {
                        Text("No matching emoji").foregroundStyle(.secondary).padding(24)
                    }
                }
                .onChange(of: model.selection) { _, _ in
                    if let row = model.selectedRow { proxy.scrollTo(row.id) }
                }
                .onChange(of: model.query) { _, _ in
                    if let row = model.rows.first { proxy.scrollTo(row.id, anchor: .top) }
                }
            }
            if case .emoji(let emoji) = model.selectedRow {
                Text(emoji.name).font(.system(size: 13)).foregroundStyle(.secondary)
                    .lineLimit(1).padding(.horizontal, 16).padding(.bottom, 8)
            }
        }
    }
}

private struct EmojiCell: View {
    let emoji: EmojiEntry
    let rowID: String
    @ObservedObject var model: LauncherModel
    private var selected: Bool { model.selectedRow?.id == rowID }
    var body: some View {
        Button { model.activate(rowID: rowID) } label: {
            Text(emoji.symbol).font(.system(size: 30))
                .frame(maxWidth: .infinity).frame(height: 52)
                .background(selected ? Color.accentColor.opacity(0.14) : Color.clear,
                            in: RoundedRectangle(cornerRadius: 8))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain).focusable(false)
        .help(emoji.name).accessibilityLabel(emoji.name)
        .accessibilityHint("Copy emoji")
        .accessibilityAddTraits(selected ? .isSelected : [])
        .id(rowID)
    }
}
