import SwiftUI
import AppKit

/// Renders parsed blocks. Code blocks and bare URLs copy their contents, never their fences.
struct MarkdownView: View {
    let text: String
    var onCopied: (String) -> Void = { _ in }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                ForEach(MarkdownBlocks.parseIndexed(text)) { item in
                    BlockView(block: item.block, onCopied: onCopied)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
        }
    }
}

private struct BlockView: View {
    let block: MarkdownBlock
    let onCopied: (String) -> Void
    @State private var hovering = false

    var body: some View {
        switch block {
        case .heading(let level, let text):
            inline(text).font(.system(size: level == 1 ? 22 : level == 2 ? 18 : 15, weight: .semibold)).padding(.top, level == 1 ? 4 : 2)
        case .paragraph(let text):
            inline(text).font(.system(size: 14)).textSelection(.enabled)
        case .quote(let text):
            HStack(spacing: 10) {
                RoundedRectangle(cornerRadius: 2).fill(Color.secondary.opacity(0.5)).frame(width: 3)
                inline(text).font(.system(size: 14)).foregroundStyle(.secondary).textSelection(.enabled)
            }
        case .list(let items, let ordered):
            VStack(alignment: .leading, spacing: 4) {
                ForEach(Array(items.enumerated()), id: \.offset) { i, item in
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(ordered ? "\(i + 1)." : "•").foregroundStyle(.secondary).frame(width: 18, alignment: .trailing)
                        inline(item).font(.system(size: 14)).textSelection(.enabled)
                    }
                }
            }
        case .rule:
            Divider()
        case .url(let url):
            copyable(label: url, mono: false, hint: "Copy URL") {
                Link(url, destination: URL(string: url)!).font(.system(size: 14)).lineLimit(1)
            }
        case .code(let lang, let code):
            copyable(label: code, mono: true, hint: lang.map { "Copy \($0)" } ?? "Copy") {
                Text(code)
                    .font(.system(size: 13, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private func inline(_ text: String) -> Text {
        if let attributed = try? AttributedString(markdown: text, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)) {
            return Text(attributed)
        }
        return Text(text)
    }

    /// Wraps a block in a rounded box with a copy button that appears on hover; clicking the box copies too.
    private func copyable<Content: View>(label: String, mono: Bool, hint: String, @ViewBuilder content: () -> Content) -> some View {
        ZStack(alignment: .topTrailing) {
            content()
                .padding(12)
                .padding(.trailing, 60)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.primary.opacity(mono ? 0.06 : 0.04), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            Button(hint) { copy(label) }
                .buttonStyle(.borderless)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
                .padding(8)
                .opacity(hovering ? 1 : 0.35)
        }
        .onHover { hovering = $0 }
        .contentShape(Rectangle())
        .onTapGesture(count: 2) { copy(label) }
    }

    private func copy(_ text: String) {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(text, forType: .string)
        onCopied(text)
    }
}
