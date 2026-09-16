import SwiftUI

struct LauncherView: View {
    @ObservedObject var model: LauncherModel
    @ObservedObject var agents: AgentsModel
    @FocusState private var focused: Bool

    private var content: some View {
        VStack(spacing: 0) {
            if model.showingDictionary {
                DictionaryView(model: model.dictionary, caffeinate: model.caffeinate, back: { model.query = ""; model.searchFocusRequest = UUID() }, copy: model.copyText)
            } else if model.showingTranslation {
                TranslationView(model: model.translation, caffeinate: model.caffeinate, back: { model.query = ""; model.searchFocusRequest = UUID() }, copy: model.copyText)
            } else {
            searchField
            Divider().opacity(0.6)
            if model.promotedHarness != nil {
                agentStatusStrip
                Divider().opacity(0.6)
            }
            if model.showingAppleShortcuts {
                HStack {
                    Text("Apple Shortcuts").foregroundStyle(.secondary)
                    Spacer()
                    Button("Refresh") { model.appleShortcuts.refresh(force: true) }
                        .disabled(model.appleShortcuts.loading)
                    Button("Open Shortcuts") { model.appleShortcuts.openApp() }
                }.font(.system(size: 12)).padding(.horizontal, 20).padding(.vertical, 6)
            }
            if !model.showingACP {
                ACPActivityStrip(model: model.acp) { model.query = "acp" }
            }
            if model.showingAgents, let message = agents.actionMessage {
                Text(message).font(.system(size: 12)).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 20).padding(.vertical, 8)
            }
            if let feedback = model.actionFeedback {
                Text(feedback).font(.system(size: 12)).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 20).padding(.vertical, 8)
                    .accessibilityLabel("Status: " + feedback)
            }
            if let network = model.wifiJoin {
                WiFiJoinView(model: model, network: network).id(network.id)
            } else if model.showingEmoji {
                EmojiGridView(model: model)
            } else if model.showingACP {
                ACPConversationView(model: model.acp)
            } else {
                if model.showingAgents {
                    HStack {
                        Text("Herdr panes").foregroundStyle(.secondary)
                        Spacer()
                        if model.promotedHarness == nil {
                            Button(agents.connected ? "Disconnect" : "Connect") {
                                if agents.connected { agents.disconnect() } else { agents.connect() }
                            }
                        }
                        Button("New ACP conversation") { model.query = "acp" }
                    }.font(.system(size: 12)).padding(.horizontal, 20).padding(.vertical, 6)
                }
                results
            }
            Divider().opacity(0.6)
            if !model.showingACP && model.wifiJoin == nil { footer }
            }
        }
        .frame(width: LauncherPanel.size.width, height: LauncherPanel.size.height)
        .background(.regularMaterial.opacity(LauncherPanel.opacity))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Color.primary.opacity(0.08)))
        .overlay(alignment: .bottomTrailing) {
            if let target = model.actionTarget {
                ZStack(alignment: .bottomTrailing) {
                    Button { closeActions() } label: { Color.clear.contentShape(Rectangle()) }
                        .buttonStyle(.plain).accessibilityLabel("Close actions")
                    LauncherActionsView(model: model, target: target, close: closeActions)
                        .id(target.id).padding(.trailing, 12).padding(.bottom, 48)
                }
            }
        }
    }

    var body: some View {
        content
        .onAppear { requestSearchFocus() }
        .onChange(of: model.query) { _, _ in model.actionTarget = nil }
        .onChange(of: model.showingEmoji) { _, _ in requestSearchFocus() }
        .onChange(of: model.selectedRow?.id) { _, _ in model.actionTarget = nil }
        .onChange(of: model.actionTarget?.id) { old, new in if old != nil && new == nil { requestSearchFocus() } }
        .onChange(of: model.searchFocusRequest) { _, _ in requestSearchFocus() }
        .onKeyPress(.downArrow) { guard model.actionTarget == nil && !model.showingDictionary && !model.showingTranslation && !model.showingACP && model.wifiJoin == nil else { return .ignored }; if model.showingEmoji { model.moveEmojiSelection(LauncherModel.emojiColumns) } else { model.moveSelection(1) }; return .handled }
        .onKeyPress(.upArrow) { guard model.actionTarget == nil && !model.showingDictionary && !model.showingTranslation && !model.showingACP && model.wifiJoin == nil else { return .ignored }; if model.showingEmoji { model.moveEmojiSelection(-LauncherModel.emojiColumns) } else { model.moveSelection(-1) }; return .handled }
        .onKeyPress(.leftArrow) { guard model.showingEmoji else { return .ignored }; model.moveEmojiSelection(-1); return .handled }
        .onKeyPress(.rightArrow) { guard model.showingEmoji else { return .ignored }; model.moveEmojiSelection(1); return .handled }
        .onKeyPress(.escape) {
            if model.actionTarget != nil { closeActions(); return .handled }
            if model.wifiJoin != nil { guard !model.connectivityBusy else { return .handled }; model.wifiJoin = nil; model.searchFocusRequest = UUID() }
            else { model.dismiss() }
            return .handled
        }
        .onKeyPress(.return, phases: .down) { press in
            guard model.actionTarget == nil && !model.showingDictionary && !model.showingTranslation && !model.showingACP && model.wifiJoin == nil else { return .ignored }
            if press.modifiers.contains(.command) { model.activateSecondary() } else { model.activateSelection() }
            return .handled
        }
    }

    private func closeActions() {
        model.actionTarget = nil
        requestSearchFocus()
    }

    private var searchField: some View {
        HStack(spacing: 14) {
            Image("VolantWing")
                .renderingMode(.template)
                .resizable()
                .scaledToFit()
                .frame(width: 24, height: 24)
                .foregroundStyle(Color.accentColor)
                .accessibilityHidden(true)
                .overlay(LauncherDragHandle())
                .help("Drag to align Volant. Hold Option to move freely.")
            if model.showingACP || model.wifiJoin != nil { CaffeinateStatusView(service: model.caffeinate) }
            TextField(model.showingEmoji ? "Search emoji…" : "Search for apps, files, contacts, or calculate…", text: Binding(get: { model.searchText }, set: { model.searchText = $0 }))
                .textFieldStyle(.plain)
                .font(.system(size: 22, weight: .regular))
                .focused($focused)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
    }

    private var agentStatusStrip: some View {
        HarnessStatusStrip(title: model.promotedTitle,
                           sessions: model.promotedHarness == nil ? agents.sessions : model.promotedSessions,
                           connected: agents.connected, busy: agents.busy,
                           pinned: model.promotedHarness != nil,
                           onOpen: { model.showPromotedAgents() },
                           onConnect: { if agents.connected { agents.disconnect() } else { agents.connect() } },
                           onPromote: { model.promoteHarness($0) })
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
                            if case .agentSession(let session) = row {
                                resultButton(row)
                                    .contextMenu {
                                        if Preferences.harnessOptions.contains(where: { $0.id == session.agent }) {
                                            Button("Show \(session.provider) in status bar") { model.promoteHarness(session.agent) }
                                        }
                                    }
                            } else {
                                resultButton(row)
                            }
                        }
                    }
                    if model.sections.isEmpty {
                        Text(model.notice ?? (model.query.isEmpty ? "Type to search" : "No results"))
                            .foregroundStyle(.secondary)
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

    private func requestSearchFocus() {
        guard model.actionTarget == nil && !model.showingDictionary && !model.showingTranslation else { return }
        // A persistent hosting view does not appear again each time its panel is summoned.
        focused = false
        DispatchQueue.main.async { focused = true }
    }

    private func resultButton(_ row: ResultRow) -> some View {
        Button { model.activate(rowID: row.id) } label: {
            RowView(initialRow: row, model: model)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .focusable(false)
        .id(row.id)
    }

    private var footer: some View {
        HStack(spacing: 18) {
            Image("VolantWing")
                .renderingMode(.template)
                .resizable()
                .scaledToFit()
                .frame(width: 16, height: 16)
                .foregroundStyle(Color.accentColor)
                .accessibilityHidden(true)
            CaffeinateStatusView(service: model.caffeinate)
            Spacer()
            if let row = model.selectedRow {
                if row.supportsActions {
                    Button { model.toggleActions() } label: {
                        HStack(spacing: 5) { Text("Actions"); KeyCap("⌘"); KeyCap("K") }
                    }.keyboardShortcut("k", modifiers: .command)
                }
                HStack(spacing: 8) {
                    Text(row.primaryAction).font(.system(size: 13, weight: .medium))
                    KeyCap("↩")
                }
                if !row.supportsActions, let secondary = row.secondaryAction {
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

struct KeyCap: View {
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
    let initialRow: ResultRow
    private var row: ResultRow { model.rows.first(where: { $0.id == initialRow.id }) ?? initialRow }
    // Lazy rows must observe selection themselves; parent closure updates can retain stale styling.
    @ObservedObject var model: LauncherModel
    private var selected: Bool { model.selectedRow?.id == row.id }

    var body: some View {
        HStack(spacing: 12) {
            icon.frame(width: 24, height: 24)
            Text(title).font(.system(size: 15)).lineLimit(1)
            if let subtitle {
                Text(subtitle).font(.system(size: 14)).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer(minLength: 12)
            if row.isCoreCommand {
                Image("VolantWing").renderingMode(.template).resizable().scaledToFit()
                    .frame(width: 14, height: 14).foregroundStyle(Color.accentColor)
                    .help("Built into Volant").accessibilityLabel("Volant built-in command")
            }
            Text(row.kind).font(.system(size: 14)).foregroundStyle(.secondary)
        }
        .padding(.horizontal, 12)
        .frame(height: 40)
        .accessibilityAddTraits(selected ? .isSelected : [])
        .background(selected ? Color.accentColor.opacity(0.14) : Color.clear, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private var title: String {
        switch row {
        case .appleShortcut(let shortcut): return shortcut.name
        case .core(let command): return command.title
        case .caffeinate(let command): return command.title
        case .agentSession(let session): return session.project
        case .connectivity(let item): return item.title
        case .audioRoute(let route): return route.name
        case .volume(let command, _): return command.title
        case .agents: return "Open Agents"
        case .calculation(let s): return "= \(s)"
        case .unit(let s): return s
        case .systemSettings(let pane): return pane.title
        case .settings: return "Volant Settings"
        case .reloadConfig: return "Reload Configuration"
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
        case .core(let command): return command.detail
        case .caffeinate(let command): return command.detail
        case .systemSettings: return "Open this pane in System Settings"
        case .settings: return "Preferences, app shortcuts and backups"
        case .reloadConfig: return "Apply changes from config.json"
        case .agentSession(let session): return session.provider + " · " + session.paneID
        case .connectivity(let item): return item.detail
        case .audioRoute(let route): return route.direction.rawValue.capitalized
        case .volume(_, let detail): return detail.isEmpty ? nil : detail
        case .agents: return "Find Herdr sessions and focus a pane"
        case .appleShortcut, .calculation, .unit, .app: return nil
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
        case .appleShortcut: Image(systemName: "square.stack.3d.up.fill").font(.system(size: 20)).foregroundStyle(.secondary)
        case .core(let command): Image(systemName: command.symbol).font(.system(size: 20)).foregroundStyle(.secondary)
        case .caffeinate: Image(systemName: "cup.and.saucer").font(.system(size: 20)).foregroundStyle(.secondary)
        case .agentSession(let session): Image(systemName: session.agentStatus == "blocked" ? "exclamationmark.bubble" : "terminal").font(.system(size: 20)).foregroundStyle(session.agentStatus == "blocked" ? Color.orange : Color.secondary)
        case .connectivity(let item): Image(systemName: item.id.hasPrefix("wifi:") ? "wifi" : "antenna.radiowaves.left.and.right").font(.system(size: 20)).foregroundStyle(.secondary)
        case .audioRoute(let route): Image(systemName: route.direction == .input ? "mic" : "speaker.wave.2").font(.system(size: 20)).foregroundStyle(.secondary)
        case .volume(let command, _): Image(systemName: command == .mute ? "speaker.slash" : "speaker.wave.2").font(.system(size: 20)).foregroundStyle(.secondary)
        case .agents: Image(systemName: "terminal").font(.system(size: 20)).foregroundStyle(.secondary)
        case .calculation: Image(systemName: "equal.circle.fill").font(.system(size: 20)).foregroundStyle(.secondary)
        case .unit: Image(systemName: "arrow.left.arrow.right.circle.fill").font(.system(size: 20)).foregroundStyle(.secondary)
        case .systemSettings, .settings: Image(systemName: "gearshape")
        case .reloadConfig: Image(systemName: "arrow.clockwise")
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
        case .emoji(let emoji): Text(emoji.symbol).font(.system(size: 20))
        case .quicklink: Image(systemName: "link").font(.system(size: 20)).foregroundStyle(.secondary)
        case .extensionRun: Image(systemName: "puzzlepiece.extension").font(.system(size: 20)).foregroundStyle(.secondary)
        case .extensionResult: Image(systemName: "checkmark.circle").font(.system(size: 20)).foregroundStyle(.secondary)
        }
    }
}
