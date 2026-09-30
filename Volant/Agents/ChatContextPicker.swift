import SwiftUI
import VolantCore

/// The @ picker: a search over recent clipboard text and notes. Results are read when the query
/// changes, not on every redraw, because clipboard history is decrypted to be searched.
struct ChatContextPicker: View {
    let candidates: (String) -> [ChatAttachment]
    let choose: (ChatAttachment) -> Void
    let close: () -> Void
    @State private var query = ""
    @State private var items: [ChatAttachment] = []
    @State private var selection = 0
    @FocusState private var focused: Bool

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "at").foregroundStyle(.secondary)
                TextField("Attach a note or clipboard item", text: $query)
                    .textFieldStyle(.plain)
                    .focused($focused)
                    .accessibilityLabel("Search notes and clipboard to attach")
                    .onKeyPress(.downArrow) { move(1); return .handled }
                    .onKeyPress(.upArrow) { move(-1); return .handled }
                    .onKeyPress(.return) { if items.indices.contains(selection) { choose(items[selection]) }; return .handled }
                    .onKeyPress(.escape) { close(); return .handled }
                Button(action: close) { Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary) }
                    .buttonStyle(.plain).help("Close").accessibilityLabel("Close attachment picker")
            }
            .padding(.horizontal, 10).padding(.vertical, 8)
            Divider()
            if items.isEmpty {
                Text(query.isEmpty ? "No notes or clipboard text yet." : "Nothing matches “\(query)”.")
                    .font(.callout).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading).padding(10)
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 2) {
                            ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                                row(item, selected: index == selection).id(item.id)
                                    .onTapGesture { choose(item) }
                            }
                        }.padding(4)
                    }
                    .frame(height: min(190, CGFloat(items.count) * 44 + 8))
                    .onChange(of: selection) { _, value in
                        if items.indices.contains(value) { proxy.scrollTo(items[value].id) }
                    }
                }
            }
        }
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous).strokeBorder(Color.primary.opacity(0.12)))
        .background(ControlAnchor("chat.picker"))
        .onAppear { refresh(); focused = true }
        .onChange(of: query) { _, _ in refresh() }
    }

    private func refresh() {
        items = candidates(query)
        selection = 0
    }

    private func move(_ delta: Int) {
        guard !items.isEmpty else { return }
        selection = min(items.count - 1, max(0, selection + delta))
    }

    private func row(_ item: ChatAttachment, selected: Bool) -> some View {
        HStack(spacing: 10) {
            Image(systemName: item.kind == .note ? "note.text" : "doc.on.clipboard")
                .frame(width: 18).foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 1) {
                Text(item.title).lineLimit(1)
                Text(item.detail + " · " + ByteCountFormatter.string(fromByteCount: Int64(item.size), countStyle: .file))
                    .font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 8).padding(.vertical, 5)
        .background(selected ? Color.accentColor.opacity(0.16) : .clear, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// One attached item above the prompt, removable with its button.
struct ChatAttachmentChip: View {
    let attachment: ChatAttachment
    let remove: () -> Void

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: attachment.kind == .note ? "note.text" : "doc.on.clipboard").font(.caption)
            Text(attachment.title).font(.caption).lineLimit(1).frame(maxWidth: 160, alignment: .leading)
            Text(ByteCountFormatter.string(fromByteCount: Int64(attachment.size), countStyle: .file))
                .font(.caption2).foregroundStyle(.secondary)
            Button(action: remove) { Image(systemName: "xmark").font(.caption2.weight(.bold)) }
                .buttonStyle(.plain).foregroundStyle(.secondary)
                .accessibilityLabel("Remove " + attachment.title)
        }
        .padding(.horizontal, 8).padding(.vertical, 4)
        .background(Color.accentColor.opacity(0.12), in: Capsule())
        .help(attachment.detail)
    }
}
