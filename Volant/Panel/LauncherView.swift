import SwiftUI

struct LauncherView: View {
    @ObservedObject var model: LauncherModel
    @FocusState private var focused: Bool

    var body: some View {
        VStack(spacing: 0) {
            searchField
            Divider().opacity(0.6)
            results
            Divider().opacity(0.6)
            footer
        }
        .frame(width: LauncherPanel.size.width, height: LauncherPanel.size.height)
        .background(.regularMaterial.opacity(LauncherPanel.opacity))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Color.primary.opacity(0.08)))
        .onAppear { DispatchQueue.main.async { focused = true } }
        .onKeyPress(.downArrow) { model.moveSelection(1); return .handled }
        .onKeyPress(.upArrow) { model.moveSelection(-1); return .handled }
        .onKeyPress(.escape) { model.dismiss(); return .handled }
        .onKeyPress(.return, phases: .down) { press in
            if press.modifiers.contains(.command) { model.activateSecondary() } else { model.activateSelection() }
            return .handled
        }
    }

    private var searchField: some View {
        HStack(spacing: 14) {
            Image("VolantWing")
                .renderingMode(.template)
                .resizable()
                .scaledToFit()
                .frame(width: 24, height: 24)
                .foregroundStyle(.tertiary)
                .accessibilityHidden(true)
            TextField("Search for apps, files, contacts, or calculate…", text: $model.query)
                .textFieldStyle(.plain)
                .font(.system(size: 22, weight: .regular))
                .focused($focused)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
    }

    private var results: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 2, pinnedViews: []) {
                    ForEach(model.sections) { section in
                        Text(section.title)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 14)
                            .padding(.top, 10)
                            .padding(.bottom, 4)
                        ForEach(section.rows) { row in
                            let offset = model.rows.firstIndex(of: row) ?? 0
                            RowView(row: row, selected: offset == model.selection)
                                .id(row.id)
                                .contentShape(Rectangle())
                                .onTapGesture { model.selection = offset; model.activateSelection() }
                        }
                    }
                    if model.sections.isEmpty {
                        Text(model.notice ?? (model.query.isEmpty ? "Type to search" : "No results"))
                            .foregroundStyle(.tertiary)
                            .padding(.top, 24)
                            .frame(maxWidth: .infinity)
                    }
                }
                .padding(.horizontal, 8)
                .padding(.bottom, 8)
            }
            .onChange(of: model.selection) { _, _ in
                if let row = model.selectedRow { proxy.scrollTo(row.id, anchor: .center) }
            }
        }
    }

    private var footer: some View {
        HStack(spacing: 18) {
            Image("VolantWing")
                .renderingMode(.template)
                .resizable()
                .scaledToFit()
                .frame(width: 16, height: 16)
                .foregroundStyle(.tertiary)
                .accessibilityHidden(true)
            Spacer()
            if let row = model.selectedRow {
                HStack(spacing: 8) {
                    Text(row.primaryAction).font(.system(size: 13, weight: .medium))
                    KeyCap("↩")
                }
                if let secondary = row.secondaryAction {
                    Divider().frame(height: 16)
                    HStack(spacing: 8) {
                        Text(secondary).font(.system(size: 13, weight: .medium)).foregroundStyle(.secondary)
                        KeyCap("⌘")
                        KeyCap("↩")
                    }
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }
}

private struct KeyCap: View {
    let symbol: String
    init(_ symbol: String) { self.symbol = symbol }
    var body: some View {
        Text(symbol)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(.secondary)
            .frame(minWidth: 22, minHeight: 20)
            .background(Color.primary.opacity(0.08), in: RoundedRectangle(cornerRadius: 5))
    }
}

private struct RowView: View {
    let row: ResultRow
    let selected: Bool

    var body: some View {
        HStack(spacing: 12) {
            icon.frame(width: 24, height: 24)
            Text(title).font(.system(size: 15)).lineLimit(1)
            if let subtitle {
                Text(subtitle).font(.system(size: 14)).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer(minLength: 12)
            Text(row.kind).font(.system(size: 14)).foregroundStyle(.secondary)
        }
        .padding(.horizontal, 12)
        .frame(height: 40)
        .background(selected ? Color.primary.opacity(0.1) : Color.clear, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private var title: String {
        switch row {
        case .calculation(let s): return "= \(s)"
        case .unit(let s): return s
        case .app(let a): return a.name
        case .file(let f): return f.name
        case .contact(let c): return c.name
        case .event(let e): return e.title
        case .clip(let c): return c.text.replacingOccurrences(of: "\n", with: " ")
        case .note(let n): return n.title
        case .newNote(let t): return "New note “\(t)”"
        case .extensionRun(let e, let i): return i.isEmpty ? e.name : "\(e.name) — \(i)"
        case .extensionResult(let s): return s
        case .snippet(let s): return s.name
        case .emoji(let e): return "\(e.symbol)  \(e.name)"
        case .quicklink(let q, let t): return t.isEmpty ? q.name : "\(q.name) — \(t)"
        }
    }

    private var subtitle: String? {
        switch row {
        case .calculation, .unit, .app: return nil
        case .file(let f): return f.url.deletingLastPathComponent().path.replacingOccurrences(of: NSHomeDirectory(), with: "~")
        case .contact(let c): return c.email ?? c.phone ?? (c.organization.isEmpty ? nil : c.organization)
        case .event(let e):
            return e.isAllDay ? "All day" : "\(e.start.formatted(date: .omitted, time: .shortened)) – \(e.end.formatted(date: .omitted, time: .shortened))"
        case .clip(let c): return c.copiedAt.formatted(date: .abbreviated, time: .shortened)
        case .note(let n): return n.preview.isEmpty ? n.modified.formatted(date: .abbreviated, time: .shortened) : n.preview
        case .newNote: return nil
        case .extensionRun(let e, _): return "\(e.manifest.id) · capabilities: \(e.manifest.capabilities.joined(separator: ", "))"
        case .extensionResult: return "Press return to copy"
        case .snippet(let s): return s.body.replacingOccurrences(of: "\n", with: " ")
        case .emoji: return nil
        case .quicklink(let q, _): return q.url
        }
    }

    @ViewBuilder private var icon: some View {
        switch row {
        case .calculation: Image(systemName: "equal.circle.fill").font(.system(size: 20)).foregroundStyle(.secondary)
        case .unit: Image(systemName: "arrow.left.arrow.right.circle.fill").font(.system(size: 20)).foregroundStyle(.secondary)
        case .app(let a): Image(nsImage: NSWorkspace.shared.icon(forFile: a.url.path)).resizable()
        case .file(let f): Image(nsImage: NSWorkspace.shared.icon(forFile: f.url.path)).resizable()
        case .contact: Image(systemName: "person.crop.circle.fill").font(.system(size: 20)).foregroundStyle(.secondary)
        case .event: Image(systemName: "calendar").font(.system(size: 20)).foregroundStyle(.secondary)
        case .clip(let c):
            if c.kind == .image, let data = c.imageData, let img = NSImage(data: data) { Image(nsImage: img).resizable().aspectRatio(contentMode: .fit) }
            else { Image(systemName: "doc.on.clipboard.fill").font(.system(size: 18)).foregroundStyle(.secondary) }
        case .note: Image(systemName: "note.text").font(.system(size: 20)).foregroundStyle(.secondary)
        case .newNote: Image(systemName: "plus.circle").font(.system(size: 20)).foregroundStyle(.secondary)
        case .snippet: Image(systemName: "text.badge.plus").font(.system(size: 20)).foregroundStyle(.secondary)
        case .emoji: Image(systemName: "face.smiling").font(.system(size: 20)).foregroundStyle(.secondary)
        case .quicklink: Image(systemName: "link").font(.system(size: 20)).foregroundStyle(.secondary)
        case .extensionRun: Image(systemName: "puzzlepiece.extension").font(.system(size: 20)).foregroundStyle(.secondary)
        case .extensionResult: Image(systemName: "checkmark.circle").font(.system(size: 20)).foregroundStyle(.secondary)
        }
    }
}
