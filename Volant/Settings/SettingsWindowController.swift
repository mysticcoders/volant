import AppKit
import SwiftUI
import ServiceManagement

final class SettingsState: ObservableObject {
    @Published var config = Preferences()
    @Published var apps: [AppEntry] = []
    @Published var section = "General"
    @Published var editing: AppEntry?
    @Published var registrationErrors: [String] = []
}

/// Native settings; the injected configuration URL also supports isolated UI fixtures.
final class SettingsWindowController: NSWindowController {
    private lazy var raycastImport = RaycastImportWindowController(onChange: onChange)
    let state = SettingsState()
    private let onChange: () -> Void
    private let configURL: URL

    init(configURL: URL = Preferences.configURL, onChange: @escaping () -> Void) {
        self.onChange = onChange
        self.configURL = configURL
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 760, height: 540),
                              styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        window.minSize = NSSize(width: 680, height: 500)
        window.title = "Volant Settings"
        window.isReleasedWhenClosed = false
        window.setFrameAutosaveName("VolantSettings")
        super.init(window: window)
        let hosting = NSHostingView(rootView: SettingsView(state: state, configURL: configURL, onChange: onChange,
                                                                  importRaycast: { [weak self] in self?.showRaycastImport() })
            .frame(minWidth: 680, idealWidth: 760, maxWidth: .infinity, minHeight: 500, idealHeight: 540, maxHeight: .infinity))
        hosting.sizingOptions = []
        let content = NSView(frame: NSRect(x: 0, y: 0, width: 760, height: 540))
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
        window.setFrame(NSWindow.frameRect(forContentRect: NSRect(x: 0, y: 0, width: 760, height: 540), styleMask: window.styleMask), display: false)
        window.center()
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    func refresh(_ config: Preferences, apps: [AppEntry]? = nil, errors: [String]? = nil) {
        state.config = config
        if let apps { state.apps = apps }
        if let errors { state.registrationErrors = errors }
    }
    func edit(_ app: AppEntry) { state.section = "App Shortcuts"; state.editing = app; showWindow(nil); NSApp.activate(ignoringOtherApps: true) }
    func showRaycastImport() { raycastImport.showWindow(nil); NSApp.activate(ignoringOtherApps: true) }
}

private struct SettingsView: View {
    @ObservedObject var state: SettingsState
    let configURL: URL
    let onChange: () -> Void
    let importRaycast: () -> Void
    @State private var search = ""
    @State private var error: String?
    @State private var loginStatus = SMAppService.mainApp.status
    private let sections = ["General", "App Shortcuts", "Data & Configuration"]

    var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Volant").font(.title2.bold()).padding(.bottom, 18)
                ForEach(sections, id: \.self) { section in
                    Button { state.section = section } label: {
                        Text(section).frame(maxWidth: .infinity, alignment: .leading).padding(10)
                            .background(state.section == section ? Color.accentColor.opacity(0.16) : .clear, in: RoundedRectangle(cornerRadius: 7))
                    }.buttonStyle(.plain)
                }
                Spacer()
            }.padding(18).frame(width: 205)
            Divider()
            VStack(alignment: .leading, spacing: 18) {
                Text(state.section).font(.title2.bold())
                if state.section == "General" { general }
                else if state.section == "App Shortcuts" { shortcuts }
                else { data }
                Spacer(minLength: 0)
            }.padding(24).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .sheet(item: $state.editing) { app in
            AppBindingEditor(app: app, configURL: configURL, onChange: onChange)
        }
        .alert("Couldn’t apply change", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
            Button("OK") { error = nil }
        } message: { Text(error ?? "") }
    }

    private var general: some View {
        ScrollView {
        VStack(alignment: .leading, spacing: 20) {
            Toggle("Show Volant in the Dock", isOn: boolean("showInDock", state.config.showInDock))
            Toggle("Show launcher when Volant starts", isOn: boolean("showOnLaunch", state.config.showOnLaunch))
            Toggle("Launch at Login", isOn: Binding(get: { loginStatus == .enabled }, set: { enabled in
                do {
                    if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
                    loginStatus = SMAppService.mainApp.status
                } catch { self.error = error.localizedDescription; loginStatus = SMAppService.mainApp.status }
            }))
            if loginStatus == .requiresApproval {
                Text("Allow Volant in System Settings → General → Login Items.").font(.callout).foregroundStyle(.secondary)
                Button("Open Login Items") { SMAppService.openSystemSettingsLoginItems() }
            }
            Divider()
            Picker("Pinned Herdr overview", selection: Binding(get: { state.config.promotedHarness ?? "" }, set: { value in
                apply { try Preferences.updatePromotedHarness(value.isEmpty ? nil : value, at: configURL) }
            })) {
                Text("None").tag("")
                ForEach(Preferences.harnessOptions, id: \.id) { Text($0.title).tag($0.id) }
            }
            Text("Show agent activity below the launcher’s search field.").font(.callout).foregroundStyle(.secondary)
            Divider()
            if !state.registrationErrors.isEmpty { Text(state.registrationErrors.joined(separator: "\n")).font(.callout).foregroundStyle(.red) }
            GlobalShortcutRow(title: "Show Volant", key: "summonHotKey", value: state.config.summonHotKey, configURL: configURL, onChange: onChange)
            GlobalShortcutRow(title: "Open Notes", key: "notesHotKey", value: state.config.notesHotKey, configURL: configURL, onChange: onChange)
            Text("Click a shortcut to record a new combination, then Save. Include Command, Control or Option.").font(.callout).foregroundStyle(.secondary)
        }.frame(maxWidth: .infinity, alignment: .leading)
        }.onAppear { loginStatus = SMAppService.mainApp.status }
    }

    private var shortcuts: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Choose an app to add a global shortcut or a short alias, such as c for Claude.").foregroundStyle(.secondary)
            TextField("Search applications", text: $search).textFieldStyle(.roundedBorder)
            if !state.registrationErrors.isEmpty {
                Text(state.registrationErrors.joined(separator: "\n")).font(.callout).foregroundStyle(.red).textSelection(.enabled)
            }
            List {
                ForEach(state.apps.filter { search.isEmpty || $0.name.localizedCaseInsensitiveContains(search) }) { app in
                    Button { state.editing = app } label: {
                        HStack {
                            Image(nsImage: NSWorkspace.shared.icon(forFile: app.url.path)).resizable().frame(width: 24, height: 24)
                            VStack(alignment: .leading) {
                                Text(app.name)
                                let aliases = state.config.aliases.filter { $0.value == app.url.path }.keys.sorted()
                                if !aliases.isEmpty { Text(aliases.joined(separator: ", ")).font(.caption).foregroundStyle(.secondary) }
                            }
                            Spacer()
                            if let id = Bundle(url: app.url)?.bundleIdentifier,
                               let key = state.config.appHotKeys.first(where: { $0.bundleIdentifier == id })?.hotKey {
                                Text(key).font(.caption).foregroundStyle(.secondary)
                            }
                            Image(systemName: "chevron.right").foregroundStyle(.secondary)
                        }.padding(.vertical, 4).contentShape(Rectangle())
                    }.buttonStyle(.plain)
                }
            }.listStyle(.inset).overlay {
                if state.apps.isEmpty { Text("No applications indexed yet. This list updates automatically.").foregroundStyle(.secondary).padding() }
            }
        }
    }

    private var data: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Configuration").font(.headline)
            Text("Keep your aliases, shortcuts and preferences in a portable JSON file.").foregroundStyle(.secondary)
            HStack {
                Button("Open Configuration…") { NSWorkspace.shared.open(configURL) }
                Button("Reveal in Finder") { NSWorkspace.shared.activateFileViewerSelecting([configURL]) }
            }
            Button("Reload Configuration") { onChange() }
            Divider()
            Text("Import & Backup").font(.headline)
            Button("Import from Raycast…", action: importRaycast)
            HStack {
                Button("Import Backup…") { if Backup.importBackup() { onChange() } }
                Button("Export Backup…") { Backup.export() }
            }
            Text("Imports show a preview before applying changes. Back up your data before moving it to another Mac.").font(.callout).foregroundStyle(.secondary)
        }
    }
    private func boolean(_ key: String, _ value: Bool) -> Binding<Bool> {
        Binding(get: { value }, set: { newValue in apply { try Preferences.updateBoolean(key, value: newValue, at: configURL) } })
    }
    private func apply(_ action: () throws -> Void) {
        do { try action(); onChange() } catch { self.error = error.localizedDescription }
    }
}
