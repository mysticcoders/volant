import AppKit
import Combine
import SwiftUI
import ServiceManagement
import VolantCore

final class SettingsState: ObservableObject {
    @Published var config = Preferences()
    @Published var apps: [AppEntry] = []
    @Published var section = SettingsSection.general
    @Published var editing: AppEntry?
    @Published var registrationErrors: [String] = []
    @Published var iCloudStatus = ICloudSettingsSync.Status.off.text
}

/// Native settings; the injected configuration URL also supports isolated UI fixtures.
final class SettingsWindowController: NSWindowController {
    private lazy var raycastImport = RaycastImportWindowController(onChange: onChange)
    let state = SettingsState()
    private let onChange: () -> Void
    private let configURL: URL
    /// Changing section replaces the detail view, but AppKit keeps the key view loop it built for the
    /// first one, so Tab from the sidebar stopped reaching the new section's controls. The loop is
    /// rebuilt after each change.
    private var sectionChanges: AnyCancellable?

    /// `dictationAccess` defaults to a real helper connection, which connects only when typing is
    /// chosen; fixtures pass one with a fake client.
    init(configURL: URL = Preferences.configURL, conversations: ACPConversations = ACPConversations(),
         dictationAccess: DictationTypingAccess = DictationTypingAccess(client: InputHostConnection()),
         openAI: @escaping (AIConfiguration) -> Void = { _ in }, onChange: @escaping () -> Void) {
        self.onChange = onChange
        self.configURL = configURL
        let window = SettingsPanel(contentRect: NSRect(x: 0, y: 0, width: 820, height: 600),
                              styleMask: [.titled, .closable, .resizable, .fullSizeContentView], backing: .buffered, defer: false)
        window.minSize = NSSize(width: 680, height: 500)
        window.title = String(localized: "Volant Settings", comment: "Settings window title")
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.toolbar = NSToolbar(identifier: "VolantSettings")
        window.toolbarStyle = .unified
        window.collectionBehavior = [.fullScreenNone]
        window.setAccessibilitySubrole(.dialog)
        window.hidesOnDeactivate = false
        window.isReleasedWhenClosed = false
        window.setFrameAutosaveName("VolantSettings")
        super.init(window: window)
        let hosting = NSHostingView(rootView: ThemedRoot(paletteText: false) {
            SettingsView(state: state, conversations: conversations, dictationAccess: dictationAccess, configURL: configURL, onChange: onChange, openAI: openAI,
                         chooseAIProject: { [weak self] completion in self?.chooseAIProject(completion) },
                         chooseAccountFolder: { [weak self] completion in self?.chooseAccountFolder(completion) },
                         importRaycast: { [weak self] in self?.showRaycastImport() })
                .frame(minWidth: 680, idealWidth: 820, maxWidth: .infinity, minHeight: 500, idealHeight: 600, maxHeight: .infinity)
                .ignoresSafeArea(.container, edges: .top)
        })
        hosting.sizingOptions = []
        let content = NSView(frame: NSRect(x: 0, y: 0, width: 820, height: 600))
        hosting.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(hosting)
        NSLayoutConstraint.activate([
            hosting.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            hosting.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            hosting.topAnchor.constraint(equalTo: content.topAnchor),
            hosting.bottomAnchor.constraint(equalTo: content.bottomAnchor)
        ])
        window.contentView = content
        window.contentMinSize = NSSize(width: 680, height: 500)
        window.setFrame(NSWindow.frameRect(forContentRect: NSRect(x: 0, y: 0, width: 820, height: 600), styleMask: window.styleMask), display: false)
        window.center()
        sectionChanges = state.$section.dropFirst().sink { [weak window] _ in
            DispatchQueue.main.async { window?.recalculateKeyViewLoop() }
        }
    }
    private func chooseAIProject(_ completion: @escaping (URL?) -> Void) {
        guard let window, window.attachedSheet == nil else { return }
        let picker = NSOpenPanel()
        picker.canChooseDirectories = true; picker.canChooseFiles = false; picker.allowsMultipleSelection = false
        picker.prompt = String(localized: "Use Project", comment: "Folder chooser button for the AI Chat working folder")
        picker.beginSheetModal(for: window) { result in completion(result == .OK ? picker.url : nil) }
    }
    /// The providers' own folders, ~/.claude and ~/.codex, are hidden, so hidden files are shown.
    /// Volant keeps only the chosen path; the agent helper passes it to the provider.
    private func chooseAccountFolder(_ completion: @escaping (URL?) -> Void) {
        guard let window, window.attachedSheet == nil else { return }
        let picker = NSOpenPanel()
        picker.canChooseDirectories = true; picker.canChooseFiles = false; picker.allowsMultipleSelection = false
        picker.showsHiddenFiles = true
        picker.prompt = String(localized: "Use Folder", comment: "Folder chooser button for an AI account folder")
        picker.message = String(localized: "Choose the folder this account signs in with.")
        picker.beginSheetModal(for: window) { result in completion(result == .OK ? picker.url : nil) }
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    func refresh(_ config: Preferences, apps: [AppEntry]? = nil, errors: [String]? = nil) {
        state.config = config
        if let apps { state.apps = apps }
        if let errors { state.registrationErrors = errors }
    }
    func edit(_ app: AppEntry) { state.section = .appShortcuts; state.editing = app; showWindow(nil); NSApp.activate(ignoringOtherApps: true) }
    func showRaycastImport() { raycastImport.showWindow(nil); NSApp.activate(ignoringOtherApps: true) }
}

private struct SettingsView: View {
    @ObservedObject var state: SettingsState
    @ObservedObject var conversations: ACPConversations
    let dictationAccess: DictationTypingAccess
    let configURL: URL
    let onChange: () -> Void
    let openAI: (AIConfiguration) -> Void
    let chooseAIProject: (@escaping (URL?) -> Void) -> Void
    let chooseAccountFolder: (@escaping (URL?) -> Void) -> Void
    let importRaycast: () -> Void
    @State private var search = ""
    @State private var sectionSearch = ""
    @Environment(\.volantTheme) private var theme
    @State private var error: String?
    @State private var loginStatus = SMAppService.mainApp.status
    /// The title band is the toolbar's height, so the traffic lights sit in the sidebar and the section
    /// title lines up with them. The split ignores the toolbar's safe area and insets the detail itself;
    /// a grouped form's scroll view still reaches under the band, so the title draws over it with an
    /// opaque background.
    private let titleBand: CGFloat = 52

    var body: some View {
        HStack(spacing: 0) {
            sidebar
                .frame(width: 220)
                .background(sidebarPane)
                .padding([.top, .leading, .bottom], 8)
            detail
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .padding(.top, titleBand)
                .overlay(alignment: .top) {
                    Text(state.section.title)
                        .font(.system(size: 15, weight: .semibold))
                        .padding(.leading, 24)
                        .frame(maxWidth: .infinity, minHeight: titleBand, maxHeight: titleBand, alignment: .leading)
                        .background(theme.windowBackground)
                        .accessibilityAddTraits(.isHeader)
                }
        }
        .background(theme.windowBackground)
        .ignoresSafeArea(.container, edges: .top)
        .sheet(item: $state.editing) { app in
            AppBindingEditor(app: app, configURL: configURL, onChange: onChange)
        }
        .alert("Couldn’t apply change", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
            Button("OK") { error = nil }
        } message: { Text(error ?? "") }
    }

    /// The sidebar floats as a rounded pane inset from the window's edges: translucent with the system
    /// themes, the palette's raised layer with a color theme.
    @ViewBuilder private var sidebarPane: some View {
        let shape = RoundedRectangle(cornerRadius: 14, style: .continuous)
        if theme.hasPalette {
            shape.fill(theme.settingsCard)
        } else {
            SidebarMaterial().clipShape(shape)
        }
    }

    /// Sections filtered by the search field, keeping core sections and features in separate groups.
    private var sidebar: some View {
        let visible = SettingsSection.allCases.filter { $0.matches(sectionSearch) }
        return VStack(spacing: 8) {
            SettingsSearchField(prompt: String(localized: "Search settings"), text: $sectionSearch) {
                if let first = visible.first { state.section = first }
            }
            .padding(.horizontal, 12)
            .padding(.top, titleBand - 8)
            List(selection: Binding(get: { state.section }, set: { if let section = $0 { state.section = section } })) {
                Section {
                    ForEach(visible.filter { !$0.isFeature }) { row($0) }
                }
                Section("Features") {
                    ForEach(visible.filter(\.isFeature)) { row($0) }
                }
            }
            .listStyle(.sidebar)
            .scrollContentBackground(.hidden)
            .overlay {
                if visible.isEmpty { Text("No matching settings").foregroundStyle(.secondary) }
            }
        }
    }

    private func row(_ section: SettingsSection) -> some View {
        Label { Text(section.title) } icon: { SettingsIcon(section: section) }
            .tag(section)
    }

    @ViewBuilder private var detail: some View {
        switch state.section {
        case .general: general
        case .appearance: AppearanceSettingsView(appearance: state.config.appearance, configURL: configURL, onChange: onChange)
        case .keyboardShortcuts: keyboardShortcuts
        case .appShortcuts: shortcuts
        case .data: data
        case .whatsNew: WhatsNewSettingsView()
        case .about: AboutSettingsView()
        case .ai: AISettingsView(conversations: conversations, configURL: configURL, onChange: onChange, openConversation: openAI, chooseProject: chooseAIProject,
                                 chooseAccountFolder: chooseAccountFolder)
        case .dictation: DictationSettingsView(config: state.config, access: dictationAccess, apply: apply, configURL: configURL)
        case .extensions: ExtensionSettingsView(configURL: configURL, onChange: onChange)
        case .fileSearch: FileSearchSettingsView(config: state.config, apply: apply, configURL: configURL)
        case .statusBar: statusBar
        }
    }

    private var general: some View {
        Form {
            Section {
                Toggle("Launch at Login", isOn: Binding(get: { loginStatus == .enabled }, set: { enabled in
                    do {
                        if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
                        loginStatus = SMAppService.mainApp.status
                    } catch { self.error = error.localizedDescription; loginStatus = SMAppService.mainApp.status }
                }))
                if loginStatus == .requiresApproval {
                    LabeledContent {
                        Button("Open Login Items") { SMAppService.openSystemSettingsLoginItems() }
                    } label: {
                        Text("Allow Volant in System Settings → General → Login Items.").foregroundStyle(.secondary)
                    }
                }
                Toggle("Show Volant in the Dock", isOn: boolean("showInDock", state.config.showInDock))
                Toggle("Show launcher when Volant starts", isOn: boolean("showOnLaunch", state.config.showOnLaunch))
            }
            LanguageSettingSection()
            Section {
                Toggle(isOn: boolean("caffeinateKeepsDisplayAwake", state.config.caffeinateKeepsDisplayAwake)) {
                    Text("Keep display on and unlocked")
                    Text("Off keeps only the Mac awake. Add display or system to a caffeinate command to choose for one session.")
                }
            } header: {
                Text("Caffeinate")
            }
        }
        .formStyle(.settings)
        .onAppear { loginStatus = SMAppService.mainApp.status }
    }

    private var keyboardShortcuts: some View {
        Form {
            Section {
                if !state.registrationErrors.isEmpty { Text(state.registrationErrors.joined(separator: "\n")).foregroundStyle(.red) }
                GlobalShortcutRow(title: String(localized: "Show Volant", comment: "Keyboard Shortcuts settings row"), key: "summonHotKey", value: state.config.summonHotKey, configURL: configURL, onChange: onChange)
                GlobalShortcutRow(title: String(localized: "Open Notes", comment: "Keyboard Shortcuts settings row"), key: "notesHotKey", value: state.config.notesHotKey, configURL: configURL, onChange: onChange)
                GlobalShortcutRow(title: String(localized: "Search Emoji", comment: "Keyboard Shortcuts settings row"), key: "emojiHotKey", value: state.config.emojiHotKey, configURL: configURL, onChange: onChange)
                GlobalShortcutRow(title: String(localized: "Dictate Text", comment: "Keyboard Shortcuts settings row"), key: "talkHotKey", value: state.config.talkHotKey, configURL: configURL, onChange: onChange)
                GlobalShortcutRow(title: String(localized: "Lock Screen", comment: "Keyboard Shortcuts settings row"), key: "lockScreenHotKey", value: state.config.lockScreenHotKey, configURL: configURL, onChange: onChange)
                GlobalShortcutRow(title: String(localized: "Sleep Displays", comment: "Keyboard Shortcuts settings row"), key: "sleepDisplaysHotKey", value: state.config.sleepDisplaysHotKey, configURL: configURL, onChange: onChange)
            } footer: {
                SettingsFooter(String(localized: "Click a shortcut and press a new combination; it saves immediately. Hold Dictate Text while you speak, or tap it to start and again to stop."))
            }
        }
        .formStyle(.settings)
    }

    private var statusBar: some View {
        Form {
            Section {
                Toggle("Herdr agent activity", isOn: Binding(get: { state.config.statusBar.sources.contains("herdr") }, set: { value in
                    apply { try Preferences.updateStatusBar(enabled: value, at: configURL) }
                }))
                LabeledContent("Agents") {
                    Picker("Agents", selection: Binding(get: { state.config.statusBar.herdrFilter }, set: { value in
                        apply { try Preferences.updateStatusBar(filter: value, at: configURL) }
                    })) {
                        ForEach(Preferences.harnessOptions, id: \.id) { Text($0.title).tag($0.id) }
                    }.labelsHidden().fixedSize()
                }.disabled(!state.config.statusBar.sources.contains("herdr"))
            } header: {
                Text("Herdr")
            } footer: {
                SettingsFooter(String(localized: "Shows “Herdr: 3 waiting” in the launcher footer when agents need you. Click it, or type herdr, to see waiting panes first and answer their questions. Includes Local and the machines enabled in Herdr."))
            }
            Section {
                Toggle("Rex pane activity", isOn: Binding(get: { state.config.statusBar.sources.contains("rex") }, set: { value in
                    apply { try Preferences.updateStatusBar(source: "rex", enabled: value, at: configURL) }
                }))
                Toggle("Pane previews in Rex Overview", isOn: boolean("rexPanePreviews", state.config.rexPanePreviews))
                    .accessibilityIdentifier("settings-rex-pane-previews")
            } header: {
                Text("Rex")
            } footer: {
                SettingsFooter(String(localized: "Shows “Rex: 2 waiting” in the launcher footer when a program in a Rex pane is waiting for you. Click it, or type rex, to see those panes first and focus one. To switch Rex to a pane in another session, turn on Remote Control in Rex Settings › Rex Server. Type rex overview to see every session and tab. Pane previews let it show the last \(RexScript.previewLines) lines of each pane’s screen, read only while the overview is open and never saved or logged; without them, Volant reads only what programs report to Rex."))
            }
            Section {
                Toggle("AI Chat activity", isOn: Binding(get: { state.config.statusBar.sources.contains("ai-chat") }, set: { value in
                    apply { try Preferences.updateStatusBar(source: "ai-chat", enabled: value, at: configURL) }
                }))
            } header: {
                Text("AI Chat")
            } footer: {
                SettingsFooter(String(localized: "Shows your active conversation below the launcher’s search field, and whether it needs you."))
            }
        }
        .formStyle(.settings)
    }

    /// App aliases and hotkeys as one card of rows under a search field, laid out like the other sections.
    private var shortcuts: some View {
        let apps = state.apps.filter { search.isEmpty || $0.name.localizedCaseInsensitiveContains(search) }
        return VStack(alignment: .leading, spacing: 10) {
            SettingsSearchField(prompt: String(localized: "Search applications"), text: $search)
            Text("Type an alias to open the app from the launcher, or record a global hotkey. Aliases save on Return or when you leave the field.")
                .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 4)
            if !state.registrationErrors.isEmpty {
                Text(state.registrationErrors.joined(separator: "\n")).font(.callout).foregroundStyle(.red).textSelection(.enabled)
                    .padding(.horizontal, 4)
            }
            HStack(spacing: 10) {
                Text("Application").frame(maxWidth: .infinity, alignment: .leading)
                Text("Alias").frame(width: 90, alignment: .leading)
                Text("Hotkey").frame(width: 160, alignment: .leading)
            }
            .font(.caption.weight(.medium)).foregroundStyle(.secondary)
            .padding(.horizontal, 16).padding(.top, 6)
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(apps) { app in
                        AppBindingRow(app: app, config: state.config, configURL: configURL, onChange: onChange)
                            .padding(.horizontal, 16).padding(.vertical, 6)
                    }
                }
                .padding(.vertical, 6)
                .background(theme.settingsCard, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .padding(.bottom, 24)
            }
            .overlay {
                if state.apps.isEmpty { Text("No applications indexed yet. This list updates automatically.").foregroundStyle(.secondary) }
                else if apps.isEmpty { Text("No matching applications").foregroundStyle(.secondary) }
            }
        }
        .padding(.horizontal, 24)
        .padding(.top, 4)
    }

    private var data: some View {
        Form {
            Section {
                LabeledContent("config.json") {
                    Button("Open") { NSWorkspace.shared.open(configURL) }
                    Button("Reveal in Finder") { NSWorkspace.shared.activateFileViewerSelecting([configURL]) }
                }
                LabeledContent("Apply edits made outside Settings") {
                    Button("Reload Configuration") { onChange() }
                }
            } header: {
                Text("Configuration")
            } footer: {
                SettingsFooter(String(localized: "Aliases, shortcuts and preferences live in one portable JSON file."))
            }
            Section {
                Toggle("Sync settings with iCloud", isOn: boolean("syncSettingsWithICloud", state.config.syncSettingsWithICloud))
                if state.config.syncSettingsWithICloud {
                    LabeledContent("Status") { Text(state.iCloudStatus).foregroundStyle(.secondary).multilineTextAlignment(.trailing) }
                }
            } header: {
                Text("iCloud")
            } footer: {
                SettingsFooter(String(localized: "Keyboard shortcuts, snippets, quicklinks, aliases, appearance and clipboard history length follow you to Macs signed in to the same Apple Account. App shortcuts, favorites, Dock, status bar, dictation, AI and extension settings stay on this Mac. When turned on, settings already in iCloud replace these, and a copy of this Mac's config.json is kept beside it."))
            }
            Section {
                LabeledContent("Raycast") {
                    Button("Import from Raycast…", action: importRaycast)
                }
                LabeledContent("Volant backup") {
                    Button("Import…") { if Backup.importBackup() { onChange() } }
                    Button("Export…") { Backup.export() }
                }
            } header: {
                Text("Import & Backup")
            } footer: {
                SettingsFooter(String(localized: "Imports show a preview before applying changes. Export a backup before moving to another Mac."))
            }
            CryptoKeySection(onChange: onChange)
        }
        .formStyle(.settings)
    }
    private func boolean(_ key: String, _ value: Bool) -> Binding<Bool> {
        Binding(get: { value }, set: { newValue in apply { try Preferences.updateBoolean(key, value: newValue, at: configURL) } })
    }
    private func apply(_ action: () throws -> Void) {
        do { try action(); onChange() } catch { self.error = error.localizedDescription }
    }
}

/// A dialog-style panel tells tiling window managers to float Settings.
final class SettingsPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override func cancelOperation(_ sender: Any?) {
        // Escape inside a recorder or sheet belongs to that control first.
        guard attachedSheet == nil else { return }
        orderOut(sender)
    }
}
