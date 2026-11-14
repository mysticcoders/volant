import SwiftUI
import VolantCore

struct LauncherView: View {
    @ObservedObject var model: LauncherModel
    /// Not observed here: Herdr refreshes every five seconds, and observing it would redraw the
    /// whole launcher, results list included. The footer status, the `herdr` header and pane rows
    /// observe it themselves.
    let agents: AgentsModel
    @FocusState private var focused: Bool
    @Environment(\.volantTheme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    /// Whether item actions or the Volant menu are open; either one owns arrow keys and Return.
    private var popoverOpen: Bool { model.actionTarget != nil || model.showingAppMenu }
    /// Whether a form below the search field owns arrow keys and Return.
    private var formOpen: Bool { model.wifiJoin != nil || model.entryForm != nil }
    private var fadesEdges: Bool { !reduceMotion && !reduceTransparency }
    /// Whether more results lie above or below the visible part of the list.
    @State private var hiddenEdges = ScrollEdges()
    /// The footer's height, so the list can scroll beneath it and still bring its last row fully into view.
    @State private var footerHeight: CGFloat = 40

    private var content: some View {
        VStack(spacing: 0) {
            if model.showingDictionary {
                DictionaryView(model: model.dictionary, caffeinate: model.caffeinate, back: { model.query = ""; model.searchFocusRequest = UUID() }, copy: model.copyText)
            } else if model.showingCatalog {
                ExtensionCatalogView(model: model.catalog, caffeinate: model.caffeinate, back: { model.query = ""; model.searchFocusRequest = UUID() })
            } else if model.showingTranslation {
                TranslationView(model: model.translation, caffeinate: model.caffeinate, back: { model.translation.clear(); model.query = ""; model.searchFocusRequest = UUID() }, copy: model.copyText)
            } else if model.showingACP {
                ACPConversationView(model: model.acp, settings: model.openAISettings, back: { model.query = "" }, caffeinate: model.caffeinate, focusRequest: model.searchFocusRequest,
                                    contextCandidates: model.contextCandidates, conversations: model.conversations,
                                    newConversation: model.newConversation, select: model.selectConversation, choose: model.chooseAIProvider, detection: model.aiDetection)
                    .onAppear { model.openAIChat() }
            } else {
            searchField
            if reduceTransparency { Divider().opacity(0.6) }
            if model.config.statusBar.sources.contains("ai-chat") {
                ACPActivityStrip(conversations: model.conversations, open: model.selectConversation)
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
            if model.showingServers {
                HStack {
                    Text("Listening Servers").foregroundStyle(.secondary)
                    Spacer()
                    Button("Refresh") { model.servers.refresh(force: true) }
                        .disabled(model.servers.loading)
                }.font(.system(size: 12)).padding(.horizontal, 20).padding(.vertical, 6)
            }
            if let network = model.wifiJoin {
                WiFiJoinView(model: model, network: network).id(network.id)
                Divider().opacity(0.6)
            } else if let draft = model.entryForm {
                LauncherEntryFormView(model: model, draft: draft).id(draft.id)
            } else if model.showingEmoji {
                EmojiGridView(model: model)
                footerBar
            } else {
                if model.showingAgents {
                    HerdrQueryHeader(agents: agents) { model.presentAIChat() }
                }
                ZStack(alignment: .bottom) {
                    results
                    footerBar
                        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { footerHeight = $0 }
                }
            }
            }
        }
        .frame(width: LauncherPanel.size.width, height: LauncherPanel.size.height)
        .sheet(item: $model.pendingExtension) { request in
            ExtensionPermissionView(request: request, enable: { model.enablePendingExtension(secrets: $0) }, cancel: { model.pendingExtension = nil })
        }
        .background(theme.surface(opacity: LauncherPanel.opacity))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(theme.separator(0.08)))
        .overlay(alignment: .top) {
            Capsule().fill(Color.secondary.opacity(0.3)).frame(width: 28, height: 3)
                .padding(.top, 4).frame(maxWidth: .infinity).frame(height: 12)
                .overlay(LauncherDragHandle())
        }
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
        .overlay(alignment: .bottomLeading) {
            if model.showingAppMenu {
                ZStack(alignment: .bottomLeading) {
                    Button { closeAppMenu() } label: { Color.clear.contentShape(Rectangle()) }
                        .buttonStyle(.plain).accessibilityLabel("Close Volant menu")
                    LauncherAppMenuView(model: model, close: closeAppMenu)
                        .padding(.leading, 12).padding(.bottom, 48)
                }
            }
        }
    }

    var body: some View {
        content
        .onAppear { requestSearchFocus() }
        .onChange(of: model.showingACP) { _, showing in if showing { focused = false } else { requestSearchFocus() } }
        .onChange(of: model.showingEmoji) { _, _ in if !focused { requestSearchFocus() } }
        .onChange(of: model.selectedRow?.id) { _, _ in model.actionTarget = nil }
        .onChange(of: model.actionTarget?.id) { old, new in if old != nil && new == nil { requestSearchFocus() } }
        .onChange(of: model.showingAppMenu) { old, new in if old && !new { requestSearchFocus() } }
        .onChange(of: model.searchFocusRequest) { _, _ in requestSearchFocus() }
        .onKeyPress(.downArrow) { if model.showingCatalog { model.catalog.moveSelection(1); return .handled }; guard !popoverOpen && !model.showingDictionary && !model.showingCatalog && !model.showingTranslation && !model.showingACP && !formOpen else { return .ignored }; if model.showingEmoji { model.moveEmojiSelection(LauncherModel.emojiColumns) } else { model.moveSelection(1) }; return .handled }
        .onKeyPress(.upArrow) { if model.showingCatalog { model.catalog.moveSelection(-1); return .handled }; guard !popoverOpen && !model.showingDictionary && !model.showingCatalog && !model.showingTranslation && !model.showingACP && !formOpen else { return .ignored }; if model.showingEmoji { model.moveEmojiSelection(-LauncherModel.emojiColumns) } else { model.moveSelection(-1) }; return .handled }
        .onKeyPress(.leftArrow) { guard model.showingEmoji else { return .ignored }; model.moveEmojiSelection(-1); return .handled }
        .onKeyPress(.rightArrow) { guard model.showingEmoji else { return .ignored }; model.moveEmojiSelection(1); return .handled }
        .onKeyPress(.escape) {
            if model.showingAppMenu { closeAppMenu(); return .handled }
            if model.actionTarget != nil { closeActions(); return .handled }
            if model.dictation.isListening { model.cancelDictation(); return .handled }
            if model.entryForm != nil { model.cancelEntryForm(); return .handled }
            if model.backOutOfScope() { return .handled }
            // Escape in AI Chat steps back to search like Back, keeping the conversation and its draft;
            // a second Escape closes the launcher.
            if model.showingACP { model.query = ""; model.searchFocusRequest = UUID(); return .handled }
            if model.wifiJoin != nil { guard !model.connectivityBusy else { return .handled }; model.wifiJoin = nil; model.searchFocusRequest = UUID() }
            else { model.dismiss() }
            return .handled
        }
        .onKeyPress(.return, phases: .down) { press in
            if model.showingCatalog && !popoverOpen {
                if press.modifiers.contains(.command) { model.catalog.openSource() } else { model.catalog.performPrimary() }
                return .handled
            }
            guard !popoverOpen && !model.showingDictionary && !model.showingCatalog && !model.showingTranslation && !model.showingACP && !formOpen else { return .ignored }
            if press.modifiers.contains(.command) && press.modifiers.contains(.shift) { model.activateSwap() }
            else if press.modifiers.contains(.command) { model.activateSecondary() } else { model.activateSelection() }
            return .handled
        }
    }

    private func closeActions() {
        model.actionTarget = nil
        requestSearchFocus()
    }

    private func closeAppMenu() {
        model.showingAppMenu = false
        requestSearchFocus()
    }

    private var searchField: some View {
        HStack(spacing: 14) {
            Image("VolantWing")
                .renderingMode(.template)
                .resizable()
                .scaledToFit()
                .frame(width: 24, height: 24)
                .foregroundStyle(.tint)
                .accessibilityHidden(true)
                .overlay(LauncherDragHandle())
                .help("Drag to align Volant. Hold Option to move freely.")
            if model.showingACP || model.wifiJoin != nil { CaffeinateStatusView(service: model.caffeinate) }
            if let ext = model.scopedExtension { ExtensionScopeChip(ext: ext, running: model.extensionRunning, back: model.exitScope) }
            if let source = model.searchScope { SearchScopeChip(source: source, back: model.exitScope) }
            TextField(model.searchPlaceholder, text: Binding(get: { model.searchText }, set: { model.searchText = $0 }))
                .textFieldStyle(.plain)
                .font(.system(size: 22, weight: .regular))
                .focused($focused)
            if let ext = model.scopedExtension, !ext.manifest.declaredFilters.isEmpty {
                ExtensionFilterMenu(filters: ext.manifest.declaredFilters, selected: model.scopeFilter, choose: model.chooseScopeFilter)
            }
            if model.canTabToAIChat {
                Button(action: model.chatFromSearch) {
                    HStack(spacing: 6) { Text("AI Chat"); Text("⇥") }
                        .font(.system(size: 12)).foregroundStyle(.secondary)
                }
                .buttonStyle(.plain).help("Open AI Chat (Tab)")
                .accessibilityLabel("Open AI Chat")
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
    }

    /// The line under the search field when there are no result rows, with a spinner while a file
    /// search is pending.
    private var emptyState: some View {
        HStack(spacing: 8) {
            if model.searchingFiles { ProgressView().controlSize(.small) }
            Text(model.emptyStateMessage).foregroundStyle(.secondary)
        }
        .padding(.top, 24)
        .frame(maxWidth: .infinity)
    }

    /// One quiet line after merged results while their file search is pending, so rows above stay put.
    private var searchingFilesLine: some View {
        HStack(spacing: 6) {
            ProgressView().controlSize(.mini)
            Text("Searching files…", comment: "Launcher status while a file search is in progress").font(.caption).foregroundStyle(.secondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .accessibilityElement(children: .combine)
    }

    private var results: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 2, pinnedViews: []) {
                    if let message = model.searchRecoveryMessage {
                        VStack(alignment: .leading, spacing: 10) {
                            Text(message).font(.callout).foregroundStyle(.secondary)
                            Button(model.searchRetryTitle) { model.retrySearch() }
                                .keyboardShortcut("r", modifiers: .command)
                        }
                        .padding(12).frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
                        .padding(.horizontal, 8)
                    }
                    if let message = model.clipboardMessage {
                        VStack(alignment: .leading, spacing: 10) {
                            Text(message).font(.callout).foregroundStyle(.secondary)
                            HStack {
                                if model.clipboardRetrying { ProgressView().controlSize(.small) }
                                Button("Retry Clipboard History") { model.retryClipboard() }
                                    .disabled(model.clipboardRetrying)
                                    .keyboardShortcut("r", modifiers: .command)
                            }
                        }
                        .padding(12).frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
                        .padding(.top, 8)
                    }
                    if let held = model.heldCalculation {
                        sectionTitle(ResultSection.calculatorTitle)
                        CalculatorCard(rowID: nil, fallback: held, state: model.rowState)
                            .id("calc-held")
                    }
                    ForEach(model.sections) { section in
                        sectionTitle(section.title)
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
                    if model.sections.isEmpty && model.clipboardMessage == nil && model.searchRecoveryMessage == nil {
                        emptyState
                    } else if model.searchingFiles {
                        searchingFilesLine
                    }
                }
                .padding(.horizontal, 8)
                .padding(.bottom, 8)
            }
            .contentMargins(.bottom, footerHeight, for: .scrollContent)
            .contentMargins(.bottom, footerHeight, for: .scrollIndicators)
            .onScrollGeometryChange(for: ScrollEdges.self, of: ScrollEdges.init) { _, edges in hiddenEdges = edges }
            .mask(EdgeFadeMask(top: fadesEdges && hiddenEdges.above, bottom: fadesEdges && hiddenEdges.below, footerHeight: footerHeight))
            .onChange(of: model.selection) { _, _ in
                if let row = model.selectedRow { proxy.scrollTo(row.id, anchor: .center) }
            }
        }
    }

    private func sectionTitle(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 14)
            .padding(.top, 10)
            .padding(.bottom, 4)
    }

    private func requestSearchFocus() {
        guard !popoverOpen && !model.showingACP && !model.showingDictionary && !model.showingCatalog && !model.showingTranslation && model.entryForm == nil else { return }
        // A persistent hosting view does not appear again each time its panel is summoned.
        focused = false
        DispatchQueue.main.async {
            guard !popoverOpen && !model.showingACP && !model.showingDictionary && !model.showingCatalog && !model.showingTranslation && model.entryForm == nil else { return }
            focused = true
        }
    }

    private func resultButton(_ row: ResultRow) -> some View {
        Button { model.activate(rowID: row.id) } label: {
            if case .calculation(let answer, _) = row {
                CalculatorCard(rowID: row.id, fallback: answer, state: model.rowState)
            } else if case .extensionItem(let item, _) = row, let forecast = item.forecast {
                ForecastCard(rowID: row.id, fallback: forecast, state: model.rowState)
            } else if case .weather(_, .report(let report)) = row {
                ForecastCard(rowID: row.id, fallback: report.forecast, attribution: report, state: model.rowState)
            } else if case .agentSession = row {
                AgentRowView(initialRow: row, state: model.rowState, agents: agents)
                    .contentShape(Rectangle())
            } else {
                RowView(initialRow: row, state: model.rowState)
                    .contentShape(Rectangle())
            }
        }
        .buttonStyle(.plain)
        .focusable(false)
        .id(row.id)
    }

    /// The footer as a bar that is translucent at its top edge and solid below it, so rows blend into
    /// it as soft shapes and colors without a hairline, as they do under the search field, while its
    /// labels sit on the solid surface and stay easy to read. A within-window blur at 60% and the theme
    /// surface both fade in over the top `footerFade` of the bar; the theme render measures the
    /// show-through in that band and the label contrast below it. Reduce Transparency uses the solid
    /// surface and keeps the hairlines, since there is nothing to blend.
    private var footerBar: some View {
        VStack(spacing: 0) {
            if reduceTransparency { Divider().opacity(0.6) }
            footer
        }
        .background {
            if reduceTransparency {
                Rectangle().fill(theme.surface(opacity: 1))
            } else {
                ZStack {
                    WithinWindowBlur().opacity(0.6)
                        .mask(LinearGradient(stops: [.init(color: .clear, location: 0), .init(color: .black, location: Self.footerFade)],
                                             startPoint: .top, endPoint: .bottom))
                    Rectangle().fill(theme.surface(opacity: 1))
                        .mask(LinearGradient(stops: [.init(color: .clear, location: 0),
                                                     .init(color: .black.opacity(0.8), location: Self.footerFade * 0.6),
                                                     .init(color: .black, location: Self.footerFade)],
                                             startPoint: .top, endPoint: .bottom))
                }
            }
        }
    }

    /// The share of the footer's height, from its top edge, over which it fades from translucent to the
    /// solid surface its labels sit on.
    private static let footerFade = 0.35

    private var footer: some View {
        HStack(spacing: 18) {
            Button { model.toggleAppMenu() } label: {
                Image("VolantWing")
                    .renderingMode(.template)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 16, height: 16)
                    .foregroundStyle(.tint)
                    .padding(4)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain).focusable(false).padding(-4)
            .help(LauncherMenuItem.versionTitle())
            .accessibilityLabel("Volant menu")
            .accessibilityIdentifier("launcher-app-menu-button")
            if let feedback = model.actionFeedback {
                Text(feedback).font(.system(size: 12)).foregroundStyle(.secondary)
                    .lineLimit(1).truncationMode(.tail).help(feedback)
                    .accessibilityLabel(String(localized: "Status: \(feedback)", comment: "Accessibility label for the footer feedback line")).layoutPriority(-1)
            }
            DictationStatusView(dictation: model.dictation)
            CaffeinateStatusView(service: model.caffeinate)
            if let filter = model.promotedHarness {
                HerdrFooterStatus(agents: agents, filter: filter, onOpen: { model.showPromotedAgents() },
                                  onConfigure: { model.promoteHarness($0) })
            }
            if model.showsRexStatus {
                RexFooterStatus(rex: model.rex, onOpen: { model.query = "rex" }, onHide: { model.setRexStatusShown(false) })
            }
            Spacer(minLength: 8)
            if let row = model.selectedRow {
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
                if case .calculation(let answer, _) = row, answer.swapQuery != nil {
                    Divider().frame(height: 16)
                    HStack(spacing: 8) {
                        Text("Swap").font(.system(size: 13, weight: .medium)).foregroundStyle(.secondary)
                        KeyCap("⇧")
                        KeyCap("⌘")
                        KeyCap("↩")
                    }
                }
                if row.supportsActions {
                    Button { model.toggleActions() } label: {
                        HStack(spacing: 5) { Text("Actions"); KeyCap("⌘"); KeyCap("K") }
                    }.keyboardShortcut("k", modifiers: .command)
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

/// Draws a command's glyph filled and white on a tinted rounded square, sized to sit level with
/// the full-color app icons in the rows around it.
private struct CommandTile: View {
    let symbol: String
    let tint: Color

    var body: some View {
        RoundedRectangle(cornerRadius: 5.5, style: .continuous)
            .fill(tint.gradient)
            .frame(width: 22, height: 22)
            .overlay {
                Image(systemName: symbol).symbolVariant(.fill)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white)
            }
            .shadow(color: .black.opacity(0.18), radius: 0.5, y: 0.5)
            .accessibilityHidden(true)
    }
}

/// A picked color as a tile the size of a command tile, outlined so white and near-background
/// colors stay visible in both appearances.
private struct ColorSwatchTile: View {
    let color: PickedColor

    var body: some View {
        RoundedRectangle(cornerRadius: 5.5, style: .continuous)
            .fill(Color(.sRGB, red: color.red, green: color.green, blue: color.blue, opacity: 1))
            .frame(width: 22, height: 22)
            .overlay(RoundedRectangle(cornerRadius: 5.5, style: .continuous).strokeBorder(Color.primary.opacity(0.2), lineWidth: 0.5))
            .accessibilityHidden(true)
    }
}

/// A server's runtime logo, in its brand color on a white tile like an app icon, so a brand color
/// is never altered and reads the same in light and dark appearance. Callers fall back to the
/// generic tile when the logo isn't in the bundle, so a tile is never left blank.
private struct RuntimeTile: View {
    let image: NSImage
    let hex: String

    private var color: Color {
        let value = UInt32(hex, radix: 16) ?? 0
        return Color(red: Double(value >> 16 & 0xFF) / 255, green: Double(value >> 8 & 0xFF) / 255, blue: Double(value & 0xFF) / 255)
    }

    var body: some View {
        RoundedRectangle(cornerRadius: 5.5, style: .continuous)
            .fill(Color.white)
            .frame(width: 22, height: 22)
            .overlay {
                Image(nsImage: image).renderingMode(.template).resizable().scaledToFit()
                    .foregroundStyle(color)
                    .frame(width: 14, height: 14)
            }
            .overlay(RoundedRectangle(cornerRadius: 5.5, style: .continuous).strokeBorder(.black.opacity(0.1), lineWidth: 0.5))
            .shadow(color: .black.opacity(0.18), radius: 0.5, y: 0.5)
            .accessibilityHidden(true)
    }
}

private extension SystemAction {
    /// Actions that end the session or power off read in red, so they stand apart from locking
    /// and sleeping, which are harmless to choose by mistake.
    var tint: Color { loginwindowEvent == nil ? .indigo : .red }
}

private extension CoreCommand {
    /// Keeps related commands in one color family so the list reads by kind at a glance.
    var tint: Color {
        switch self {
        case .ai: return .purple
        case .talk: return .red
        case .confetti: return .pink
        case .shortcuts: return .indigo
        case .define: return .brown
        case .translate: return .teal
        case .caffeinate: return .orange
        case .emoji: return .green
        case .notes: return Color(red: 0.93, green: 0.66, blue: 0.0)
        case .clipboard: return Color(red: 0.36, green: 0.46, blue: 0.62)
        case .contacts: return Color(red: 0.55, green: 0.45, blue: 0.35)
        case .files: return .cyan
        case .agents: return Color(white: 0.22)
        case .servers: return Color(red: 0.2, green: 0.55, blue: 0.35)
        case .wifi, .bluetooth: return .blue
        case .audio: return .mint
        case .colorPicker: return Color(red: 0.85, green: 0.35, blue: 0.55)
        case .camera: return Color(white: 0.35)
        case .newSnippet, .newQuicklink: return .cyan
        case .catalog: return Color(red: 0.95, green: 0.42, blue: 0.29)
        case .menuItems: return Color(red: 0.35, green: 0.4, blue: 0.85)
        case .focus: return Color(red: 0.0, green: 0.55, blue: 0.5)
        case .breaks: return Color(red: 0.2, green: 0.6, blue: 0.3)
        }
    }
}

/// Herdr pane rows observe the agents model directly, because change counts and unread state
/// arrive after the pane list; other rows ignore its periodic updates.
private struct AgentRowView: View {
    let initialRow: ResultRow
    @ObservedObject var state: LauncherRowState
    @ObservedObject var agents: AgentsModel

    var body: some View {
        if case .agentSession(let session) = state.rowsByID[initialRow.id] ?? initialRow {
            RowView(initialRow: initialRow, state: state, agentUnread: agents.isUnread(session),
                    agentSummary: agents.repository(for: session)?.summary)
        } else {
            RowView(initialRow: initialRow, state: state)
        }
    }
}

private struct RowView: View {
    let initialRow: ResultRow
    private var row: ResultRow { state.rowsByID[initialRow.id] ?? initialRow }
    // Lazy rows must observe selection themselves; parent closure updates can retain stale styling.
    @ObservedObject var state: LauncherRowState
    var agentUnread = false
    var agentSummary: String?
    @Environment(\.volantTheme) private var theme
    private var selected: Bool { state.selectedID == row.id }

    var body: some View {
        HStack(spacing: 12) {
            icon.frame(width: 24, height: 24)
            Text(title).font(.system(size: 15)).lineLimit(1)
                .foregroundStyle(dimmed ? AnyShapeStyle(.tertiary) : AnyShapeStyle(.primary))
            if let subtitle {
                Text(subtitle).font(.system(size: 14)).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer(minLength: 12)
            if row.isCoreCommand {
                Image("VolantWing").renderingMode(.template).resizable().scaledToFit()
                    .frame(width: 14, height: 14).foregroundStyle(.tint)
                    .help("Built into Volant").accessibilityLabel("Volant built-in command")
            }
            if case .extensionItem(let item, _) = row, let badges = item.badges {
                ExtensionRowBadges(badges: badges)
            } else if case .menuItem(let entry) = row {
                if let shortcut = entry.item.shortcut {
                    Text(shortcut.display).font(.system(size: 12, weight: .medium)).foregroundStyle(.secondary)
                        .padding(.horizontal, 6).frame(minHeight: 20)
                        .background(Color.primary.opacity(0.08), in: RoundedRectangle(cornerRadius: 5))
                        .accessibilityLabel(String(localized: "Shortcut \(shortcut.display, format: .verbatim)", comment: "Accessibility label for a menu item's keyboard shortcut"))
                }
            } else {
                Text(row.kind).font(.system(size: 14)).foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 12)
        .frame(height: 40)
        .accessibilityAddTraits(selected ? .isSelected : [])
        .background(selected ? theme.selection : AnyShapeStyle(Color.clear), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    /// A disabled menu item, drawn dimmed; Return on it explains instead of pressing.
    private var dimmed: Bool {
        if case .menuItem(let entry) = row { return !entry.item.enabled }
        return false
    }

    private var title: String {
        switch row {
        case .appleShortcut(let shortcut): return shortcut.name
        case .menuItem(let entry): return entry.item.title
        case .menuItemsOff: return String(localized: "Turn On Search Menu Items", comment: "Launcher row title while Search Menu Items is off")
        case .server(let server): return "\(server.port) · " + (server.folderName.map { server.displayName + " · " + $0 } ?? server.displayName)
        case .core(let command): return command.title
        case .systemAction(let action): return action.title
        case .systemToggle(let toggle, _): return toggle.title
        case .pickedColor(let color, let format): return color.value(format)
        case .pickAnotherColor: return String(localized: "Pick Another Color", comment: "Launcher row title after a color was picked: open the loupe again")
        case .privacySettings(let pane): return pane.title
        case .caffeinate(let command): return command.title
        case .focus(let row, _): return row.title
        case .breaks(let row, _): return row.title
        case .agentSession(let session): return session.project
        case .herdrMachine(let machine, _, _): return machine?.label ?? String(localized: "Local", comment: "Herdr machine row title for this Mac")
        case .rexPane(let pane): return pane.project
        case .rexOverview: return String(localized: "Open Rex Overview", comment: "Launcher row title")
        case .connectivity(let item): return item.title
        case .audioRoute(let route): return route.name
        case .volume(let command, _): return command.title
        case .agents: return String(localized: "Open Agents", comment: "Launcher row title")
        case .extensionUpdates: return String(localized: "Extension Updates Available", comment: "Launcher row title")
        case .calculation(let answer, _): return answer.input + " = " + answer.result
        case .systemSettings(let pane): return pane.title
        case .settings: return String(localized: "Volant Settings", comment: "Launcher row title")
        case .reloadConfig: return String(localized: "Reload Configuration", comment: "Launcher row title")
        case .app(let a): return a.name
        case .file(let f): return f.name
        case .contact(let c): return c.name
        case .event(let e): return e.title
        case .clip(let c): return c.text.replacingOccurrences(of: "\n", with: " ")
        case .note(let n): return n.title
        case .newNote(let t): return String(localized: "New note “\(t)”", comment: "Launcher row title; the value is the typed note text")
        case .extensionRun(let e, let i): return i.isEmpty ? e.name : "\(e.name) — \(i)"
        case .extensionResult(let s): return s
        case .extensionItem(let item, _): return item.title
        case .weather(_, .report(let report)): return report.forecast.place
        case .weather(_, .message(let message)): return message
        case .weather(_, .needsLocation): return PrivacyPane.location.title
        case .snippet(let s): return s.name
        case .emoji(let e): return "\(e.symbol)  \(e.name)"
        case .quicklink(let q, let t): return t.isEmpty ? q.name : "\(q.name) — \(t)"
        }
    }

    private var subtitle: String? {
        switch row {
        case .core(let command): return command.detail
        case .server(let server): return server.detail(home: ServersModel.home)
        case .menuItem(let entry): return entry.item.location
        case .menuItemsOff: return String(localized: "Off in Settings. Lets Volant read and press the menus of the app you were using.", comment: "Launcher row subtitle while Search Menu Items is off")
        case .systemAction(let action): return action.detail
        case .systemToggle(let toggle, let on): return toggle.detail(on: on)
        case .pickedColor(_, let format): return format.label
        case .pickAnotherColor: return String(localized: "Open the loupe again", comment: "Launcher row subtitle for Pick Another Color")
        case .privacySettings(let pane): return pane.detail
        case .caffeinate(let command): return command.detail
        case .focus(_, let detail): return detail
        case .breaks(_, let detail): return detail
        case .systemSettings: return String(localized: "Open this pane in System Settings", comment: "Launcher row subtitle")
        case .settings: return String(localized: "Preferences, app shortcuts and backups", comment: "Launcher row subtitle for Volant Settings")
        case .reloadConfig: return String(localized: "Apply changes from config.json", comment: "Launcher row subtitle for Reload Configuration")
        case .agentSession(let session):
            return session.machineLabel + " · " + session.provider + " · " + (agentSummary ?? session.paneID)
        case .herdrMachine(let machine, _, _): return machine.map { $0.target + " · " + $0.session } ?? String(localized: "This Mac", comment: "Herdr machine row subtitle for the local machine")
        case .rexPane(let pane):
            return ([pane.sessionLabel, pane.program] + [pane.status?.message ?? pane.label]).compactMap { $0 }.joined(separator: " · ")
        case .rexOverview: return String(localized: "Every session and tab in a window", comment: "Launcher row subtitle for Rex Overview")
        case .connectivity(let item): return item.detail
        case .audioRoute(let route): return route.direction == .output ? String(localized: "Output", comment: "Audio device row subtitle") : String(localized: "Input", comment: "Audio device row subtitle")
        case .volume(_, let detail): return detail.isEmpty ? nil : detail
        case .agents: return String(localized: "Find Herdr sessions and focus a pane", comment: "Launcher row subtitle for Open Agents")
        case .extensionUpdates(let names): return names
        case .appleShortcut, .calculation, .app: return nil
        case .file(let f): return f.url.deletingLastPathComponent().path.replacingOccurrences(of: UserHome.path, with: "~")
        case .contact(let c): return c.email ?? c.phone ?? (c.organization.isEmpty ? nil : c.organization)
        case .event(let e):
            return e.isAllDay ? String(localized: "All day", comment: "Calendar event row subtitle") : "\(e.start.formatted(date: .omitted, time: .shortened)) – \(e.end.formatted(date: .omitted, time: .shortened))"
        case .clip(let c): return c.copiedAt.formatted(date: .abbreviated, time: .shortened)
        case .note(let n): return n.preview.isEmpty ? n.modified.formatted(date: .abbreviated, time: .shortened) : n.preview
        case .newNote: return nil
        case .extensionRun(let e, _):
            return e.communityBlocked ? String(localized: "Community extensions off · \(e.accessDescription)", comment: "Extension row subtitle; the value describes the extension's access")
                : (e.enabled ? String(localized: "Enabled · \(e.accessDescription)", comment: "Extension row subtitle; the value describes the extension's access") : String(localized: "Off · \(e.accessDescription)", comment: "Extension row subtitle; the value describes the extension's access"))
        case .extensionResult: return String(localized: "Press return to copy", comment: "Extension result row subtitle")
        case .extensionItem(let item, _): return item.subtitle ?? item.url ?? ""
        case .weather(_, .report(let report)): return report.forecast.condition
        case .weather(_, .message), .weather(_, .needsLocation): return nil
        case .snippet(let s): return s.body.replacingOccurrences(of: "\n", with: " ")
        case .emoji: return nil
        case .quicklink(let q, _): return q.url
        }
    }

    /// A Rex pane's icon follows what its program last reported.
    private static func rexSymbol(_ state: RexState) -> String {
        switch state {
        case .blocked: return "exclamationmark.bubble"
        case .error: return "xmark.octagon"
        case .done: return "checkmark.circle"
        case .working, .idle: return "terminal"
        }
    }

    @ViewBuilder private var icon: some View {
        switch row {
        case .appleShortcut: CommandTile(symbol: "square.stack.3d.up", tint: CoreCommand.shortcuts.tint)
        case .menuItem(let entry):
            if let path = entry.appPath { Image(nsImage: state.icon(forFile: path)).resizable().opacity(dimmed ? 0.5 : 1) }
            else { CommandTile(symbol: CoreCommand.menuItems.symbol, tint: CoreCommand.menuItems.tint) }
        case .menuItemsOff: CommandTile(symbol: CoreCommand.menuItems.symbol, tint: CoreCommand.menuItems.tint)
        case .server(let server):
            if let logo = server.kind.logo, let image = NSImage(named: "Runtimes/" + logo.asset) { RuntimeTile(image: image, hex: logo.hex) }
            else { CommandTile(symbol: CoreCommand.servers.symbol, tint: CoreCommand.servers.tint) }
        case .core(let command): CommandTile(symbol: command.symbol, tint: command.tint)
        case .pickAnotherColor: CommandTile(symbol: CoreCommand.colorPicker.symbol, tint: CoreCommand.colorPicker.tint)
        case .systemAction(let action): CommandTile(symbol: action.symbol, tint: action.tint)
        case .systemToggle(let toggle, _): CommandTile(symbol: toggle.symbol, tint: .indigo)
        case .pickedColor(let color, _): ColorSwatchTile(color: color)
        case .privacySettings(let pane): CommandTile(symbol: pane.symbol, tint: .gray)
        case .caffeinate: CommandTile(symbol: "cup.and.saucer", tint: CoreCommand.caffeinate.tint)
        case .focus(let row, _): CommandTile(symbol: row.symbol, tint: CoreCommand.focus.tint)
        case .breaks(let row, _): CommandTile(symbol: row.symbol, tint: CoreCommand.breaks.tint)
        case .agentSession(let session):
            Image(systemName: session.agentStatus == "blocked" ? "exclamationmark.bubble" : "terminal").font(.system(size: 20))
                .foregroundStyle(session.agentStatus == "blocked" ? Color.orange : Color.secondary)
                .overlay(alignment: .topTrailing) {
                    if agentUnread {
                        Circle().fill(.tint).frame(width: 8, height: 8).offset(x: 3, y: -2)
                            .accessibilityLabel("Changed since you last looked")
                    }
                }
        case .rexOverview: CommandTile(symbol: "square.grid.2x2", tint: CoreCommand.agents.tint)
        case .rexPane(let pane):
            Image(systemName: Self.rexSymbol(pane.state)).font(.system(size: 20))
                .foregroundStyle(pane.state == .blocked || pane.state == .error ? Color.orange : Color.secondary)
        case .herdrMachine(let machine, let enabled, _):
            Image(systemName: machine == nil ? "desktopcomputer" : (enabled ? "network" : "network.slash"))
                .font(.system(size: 20)).foregroundStyle(enabled ? Color.secondary : Color.secondary.opacity(0.5))
        case .connectivity(let item):
            let wifi = item.id.hasPrefix("wifi:")
            CommandTile(symbol: wifi ? "wifi" : "antenna.radiowaves.left.and.right", tint: (wifi ? CoreCommand.wifi : .bluetooth).tint)
        case .audioRoute(let route): CommandTile(symbol: route.direction == .input ? "mic" : "speaker.wave.2", tint: CoreCommand.audio.tint)
        case .volume(let command, _): CommandTile(symbol: command == .mute ? "speaker.slash" : "speaker.wave.2", tint: CoreCommand.audio.tint)
        case .agents: CommandTile(symbol: "terminal", tint: CoreCommand.agents.tint)
        case .extensionUpdates: CommandTile(symbol: "arrow.down.circle", tint: Color(red: 0.95, green: 0.42, blue: 0.29))
        case .calculation: Image(systemName: "equal.circle.fill").font(.system(size: 20)).foregroundStyle(.secondary)
        case .systemSettings, .settings: CommandTile(symbol: "gearshape", tint: .gray)
        case .reloadConfig: CommandTile(symbol: "arrow.clockwise", tint: .gray)
        case .app(let a): Image(nsImage: state.icon(forFile: a.url.path)).resizable()
        case .file(let f): Image(nsImage: state.icon(forFile: f.url.path)).resizable()
        case .contact(let c):
            if let image = state.contactImages[c.id] {
                Image(nsImage: image).resizable().aspectRatio(contentMode: .fill).clipShape(Circle())
            } else {
                Image(systemName: "person.crop.circle.fill").font(.system(size: 20)).foregroundStyle(.secondary)
            }
        case .event: Image(systemName: "calendar").font(.system(size: 20)).foregroundStyle(.secondary)
        case .clip(let c):
            if c.kind == .image, let img = state.image(for: c) { Image(nsImage: img).resizable().aspectRatio(contentMode: .fit) }
            else { Image(systemName: "doc.on.clipboard.fill").font(.system(size: 18)).foregroundStyle(.secondary) }
        case .note: Image(systemName: "note.text").font(.system(size: 20)).foregroundStyle(.secondary)
        case .newNote: Image(systemName: "plus.circle").font(.system(size: 20)).foregroundStyle(.secondary)
        case .snippet: Image(systemName: "text.badge.plus").font(.system(size: 20)).foregroundStyle(.secondary)
        case .emoji(let emoji): Text(emoji.symbol).font(.system(size: 20))
        case .quicklink: Image(systemName: "link").font(.system(size: 20)).foregroundStyle(.secondary)
        case .extensionRun(let ext, _):
            if let icon = ExtensionIcon.image(for: ext) { Image(nsImage: icon).resizable().clipShape(RoundedRectangle(cornerRadius: 5)) }
            else { Image(systemName: "puzzlepiece.extension").font(.system(size: 20)).foregroundStyle(.secondary) }
        case .extensionResult: Image(systemName: "checkmark.circle").font(.system(size: 20)).foregroundStyle(.secondary)
        case .weather: Image(systemName: "cloud.sun.fill").symbolRenderingMode(.multicolor).font(.system(size: 18))
        case .extensionItem(let item, let source):
            if let image = item.image {
                ExtensionRowImage(url: image.url, source: source, images: state.extensionImages) { ExtensionItemIcon(item: item, source: source) }
            } else {
                ExtensionItemIcon(item: item, source: source)
            }
        }
    }
}

/// A list extension row's own icon: the symbol it chose, otherwise the extension's icon, otherwise a
/// generic symbol. Also the placeholder while a row image loads and when it fails.
struct ExtensionItemIcon: View {
    let item: ExtensionItem
    let source: InstalledExtension

    var body: some View {
        if let symbol = item.symbol.flatMap(ExtensionItemSymbol.init(rawValue:)) {
            ExtensionRowSymbol(symbol: symbol)
        } else if let icon = ExtensionIcon.image(for: source) {
            Image(nsImage: icon).resizable().clipShape(RoundedRectangle(cornerRadius: 5))
        } else {
            Image(systemName: "newspaper").font(.system(size: 20)).foregroundStyle(.secondary)
        }
    }
}

/// A list extension row's image preview, such as a favicon, drawn aspect-fit and rounded at the row's
/// 24-point icon size. It asks for its image when the row appears, and again when a new list keeps the
/// row on screen, so only rows on screen load. It shows `placeholder` until the image arrives, or for
/// good when it fails.
struct ExtensionRowImage<Placeholder: View>: View {
    let url: String
    let source: InstalledExtension
    @ObservedObject var images: ExtensionRowImages
    @ViewBuilder let placeholder: () -> Placeholder

    var body: some View {
        Group {
            if let image = images.image(url, for: source) {
                Image(nsImage: image).resizable().interpolation(.high).aspectRatio(contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
                    .accessibilityHidden(true)
            } else {
                placeholder()
            }
        }
        .frame(width: 24, height: 24)
        .onAppear { images.request(url, for: source) }
        .onChange(of: images.list) { images.request(url, for: source) }
    }
}


/// Shows that the microphone is live and what has been heard so far, so dictation is never
/// running invisibly.
struct DictationStatusView: View {
    @ObservedObject var dictation: SpeechDictation

    var body: some View {
        if dictation.phase == .listening || dictation.phase == .finishing {
            HStack(spacing: 6) {
                Image(systemName: dictation.phase == .listening ? "mic.fill" : "waveform")
                    .font(.system(size: 12))
                    .foregroundStyle(dictation.phase == .listening ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
                    .accessibilityLabel(dictation.phase == .listening ? String(localized: "Listening", comment: "Dictation status accessibility label") : String(localized: "Transcribing", comment: "Dictation status accessibility label"))
                if !dictation.transcript.isEmpty {
                    Text(dictation.transcript).font(.system(size: 12)).foregroundStyle(.secondary)
                        .lineLimit(1).truncationMode(.head)
                        .accessibilityLabel(String(localized: "Heard so far: \(dictation.transcript)", comment: "Accessibility label for the live dictation transcript"))
                }
            }
        }
    }
}

/// Which ends of a scroll view have content beyond the visible area.
struct ScrollEdges: Equatable {
    var above = false
    var below = false

    init() {}

    init(_ geometry: ScrollGeometry) {
        let insets = geometry.contentInsets
        above = geometry.contentOffset.y > -insets.top + 1
        below = geometry.contentOffset.y + geometry.containerSize.height < geometry.contentSize.height + insets.bottom - 1
    }
}

/// Fades the results list over a short band at an edge only while more results lie beyond it, so
/// rows blend under the search field and footer as they scroll, and the first and last rows are
/// never dimmed once the list reaches its end.
struct EdgeFadeMask: View {
    let top: Bool
    let bottom: Bool
    /// Rows beneath the footer stay fully drawn so they show through its blur; the bottom band
    /// eases only the strip just above the footer's top edge.
    var footerHeight: CGFloat = 0
    private let topBand: CGFloat = 36
    private let bottomBand: CGFloat = 20

    var body: some View {
        VStack(spacing: 0) {
            LinearGradient(colors: [.black.opacity(top ? 0.25 : 1), .black], startPoint: .top, endPoint: .bottom).frame(height: topBand)
            Color.black
            LinearGradient(colors: [.black, .black.opacity(bottom ? 0.7 : 1)], startPoint: .top, endPoint: .bottom).frame(height: bottomBand)
            Color.black.frame(height: footerHeight)
        }
    }
}

/// A blur of the window's own content behind it, unlike a SwiftUI material inside this panel,
/// which picked up only the panel background and hid the rows passing under the footer.
struct WithinWindowBlur: NSViewRepresentable {
    var material: NSVisualEffectView.Material = .menu

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = .withinWindow
        view.state = .active
        return view
    }

    func updateNSView(_ view: NSVisualEffectView, context: Context) {
        view.material = material
    }
}

/// A row icon an extension chose from `ExtensionItemSymbol`, in full color. Multicolor clouds are
/// white, so in light appearance a soft edge keeps them visible against the launcher.
struct ExtensionRowSymbol: View {
    let symbol: ExtensionItemSymbol
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Image(systemName: symbol.systemName)
            .symbolRenderingMode(.multicolor)
            .font(.system(size: 18))
            .shadow(color: .black.opacity(colorScheme == .dark ? 0 : 0.45), radius: 1, y: 0.5)
            .accessibilityLabel(symbol.rawValue.replacingOccurrences(of: "-", with: " "))
    }
}

/// The Back chip at the start of the search field while the launcher is inside a list extension: its
/// icon and name, with a spinner while it runs. Clicking it, or Escape or Delete on an empty field, goes back.
private struct ExtensionScopeChip: View {
    let ext: InstalledExtension
    let running: Bool
    let back: () -> Void

    var body: some View {
        Button(action: back) {
            HStack(spacing: 6) {
                Image(systemName: "chevron.left").font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary)
                if let icon = ExtensionIcon.image(for: ext) {
                    Image(nsImage: icon).resizable().interpolation(.high).frame(width: 16, height: 16)
                }
                Text(ext.name).lineLimit(1)
                if running { ProgressView().controlSize(.mini) }
            }
            .font(.system(size: 13, weight: .medium))
            .padding(.horizontal, 8).padding(.vertical, 4)
            .background(Color.secondary.opacity(0.15), in: Capsule())
        }
        .buttonStyle(.plain)
        .help("Back to Volant (Esc)")
        .accessibilityLabel("Back from \(ext.name)")
        .accessibilityIdentifier("launcher-extension-back")
    }
}

/// The Back chip inside Volant's own Contacts, Files or Clipboard scope, shaped like an extension's.
private struct SearchScopeChip: View {
    let source: SearchScope
    let back: () -> Void

    var body: some View {
        Button(action: back) {
            HStack(spacing: 6) {
                Image(systemName: "chevron.left").font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary)
                Image(systemName: source.command.symbol).font(.system(size: 13)).foregroundStyle(source.command.tint)
                Text(source.title).lineLimit(1)
            }
            .font(.system(size: 13, weight: .medium))
            .padding(.horizontal, 8).padding(.vertical, 4)
            .background(Color.secondary.opacity(0.15), in: Capsule())
        }
        .buttonStyle(.plain)
        .help("Back to Volant (Esc)")
        .accessibilityLabel("Back from \(source.title)")
        .accessibilityIdentifier("launcher-scope-back")
    }
}

/// The short facts a list extension shows at a row's end, such as points, comments and the linked
/// site, each with its symbol. They take the place of the extension's name.
private struct ExtensionRowBadges: View {
    let badges: [ExtensionItemBadge]

    var body: some View {
        HStack(spacing: 12) {
            ForEach(Array(badges.enumerated()), id: \.offset) { _, badge in
                let symbol = badge.symbol.flatMap(ExtensionItemBadge.Symbol.init(rawValue:))
                HStack(spacing: 4) {
                    if let symbol { Image(systemName: symbol.systemName).font(.system(size: 11, weight: .medium)) }
                    Text(badge.text).monospacedDigit().lineLimit(1)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(symbol.map { "\($0.spokenName): \(badge.text)" } ?? badge.text)
            }
        }
        .font(.system(size: 13))
        .foregroundStyle(.secondary)
        .fixedSize()
    }
}

/// The dropdown at the end of the search field inside a list extension that declares `filters`, such
/// as Top, New and Ask. Choosing an entry runs the extension at once; Command-P chooses the next one.
private struct ExtensionFilterMenu: View {
    let filters: [ExtensionFilter]
    let selected: String?
    let choose: (String) -> Void

    var body: some View {
        Menu {
            ForEach(filters, id: \.id) { filter in
                Button { choose(filter.id) } label: {
                    if filter.id == selected { Label(filter.title, systemImage: "checkmark") } else { Text(filter.title) }
                }
            }
        } label: {
            Text(filters.first { $0.id == selected }?.title ?? filters[0].title)
        }
        .menuStyle(.button)
        .buttonStyle(.bordered)
        .controlSize(.regular)
        .fixedSize()
        .help("Filter (⌘P for the next one)")
        .accessibilityLabel("Filter")
        .accessibilityIdentifier("launcher-extension-filter")
    }
}

