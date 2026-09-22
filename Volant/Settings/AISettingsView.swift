import AppKit
import SwiftUI
import VolantCore

struct AISettingsView: View {
    @ObservedObject var model: ACPModel
    let configURL: URL
    let onChange: () -> Void
    let openConversation: (AIConfiguration) -> Void
    let chooseProject: (@escaping (URL?) -> Void) -> Void
    var credentials = AICredentials.keychain
    @StateObject var discovery = AIModelDiscovery()
    @State private var config = AIConfiguration()
    @State private var saved = AIConfiguration()
    @State private var feedback: String?
    @State private var failed = false
    @State private var loaded = false
    @State private var keyDraft = ""
    var body: some View {
        Form {
            Section {
                Picker("Connection", selection: $config.connection) {
                    ForEach(AIConnectionKind.allCases) { Text($0.title).tag($0) }
                }.pickerStyle(.segmented).disabled(!loaded)
                    .onChange(of: config.connection) { _, kind in
                        keyDraft = ""; discovery.cancel(); persist()
                        if kind == .local { discovery.discover() }
                    }
            }
            if config.connection == .acp { acpControls }
            else if config.connection == .apple { appleControls }
            else { apiControls }
            Section {
                if model.active {
                    LabeledContent("Current conversation: \(model.providerTitle)") {
                        Button("Open Current Conversation") { openConversation(config) }
                    }
                } else {
                    LabeledContent(config.isConfigured ? "Ready" : "Finish the settings above to connect") {
                        Button(config.connection == .acp ? "Connect ACP" : "Open AI Chat") {
                            if persist() { openConversation(config) }
                        }.disabled(!config.isConfigured || !loaded || (config.connection == .apple && !appleAvailability.isReady))
                            .background(ControlAnchor("settings.connect"))
                    }
                }
            } footer: {
                VStack(alignment: .leading, spacing: 4) {
                    if model.active { Text("Settings apply to the next conversation.") }
                    if let feedback {
                        Text(feedback).foregroundStyle(failed ? Color.red : Color.secondary).accessibilityLabel(feedback)
                    }
                }.font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.leading).frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .formStyle(.grouped)
        .onAppear {
            do {
                config = try AIConfiguration.load(at: configURL); saved = config; loaded = true
                if config.connection == .local { discovery.discover() }
            } catch { report("Couldn’t load AI settings. Fix or reload the configuration before editing.", failure: true) }
        }
        .onChange(of: config.http.endpoint) { _, _ in discovery.endpointChanged(config.http.endpoint); keyDraft = "" }
        .onDisappear { discovery.cancel(); keyDraft = ""; if loaded && config != saved { persist() } }
    }
    private var appleAvailability: AppleFoundationModel.Availability { AppleFoundationModel.availability }

    /// Apple's model has nothing to configure. What matters is whether it can run here at all, and
    /// the reason is shown rather than leaving a disabled button unexplained.
    private var appleControls: some View {
        Section {
            if let reason = appleAvailability.reason {
                Label(reason, systemImage: "exclamationmark.triangle").foregroundStyle(.secondary)
            } else {
                Label("Available on this Mac.", systemImage: "checkmark.circle")
            }
        } header: {
            Text("Apple Intelligence")
        } footer: {
            SettingsFooter("Runs Apple's on-device model. No API key, no network request and no helper process; the conversation stays on this Mac.")
        }
    }

    private var acpControls: some View {
        Section {
            Picker("Provider", selection: $config.provider) {
                Text("Choose a provider…").tag("")
                ForEach(ACPProvider.allCases) { Text($0.title).tag($0.rawValue) }
            }.disabled(!loaded).onChange(of: config.provider) { _, _ in persist() }
            LabeledContent("Working folder") {
                Text(config.project.isEmpty ? "General chat" : URL(fileURLWithPath: config.project).lastPathComponent)
                    .lineLimit(1).help(config.project).foregroundStyle(.secondary)
                if !config.project.isEmpty { Button("Clear") { config.project = ""; persist() }.help("Use General Chat") }
                Button("Choose Folder…") { chooseProject { url in if let url { config.project = url.path; persist() } } }.disabled(!loaded)
                    .background(ControlAnchor("settings.choose-folder"))
            }
        } header: {
            Text("ACP")
        } footer: {
            SettingsFooter("Uses your agent’s existing CLI login; sign in with that provider first. A working folder is optional and is not a sandbox: your agent’s permissions still control tool access.")
        }
    }
    private var httpBinding: Binding<AIHTTPConfiguration> {
        Binding(get: { config.http }, set: { if config.connection == .local { config.localAPI = $0 } else { config.api = $0 } })
    }
    @ViewBuilder private var apiControls: some View {
        if config.connection == .local { localServers }
        Section {
            if config.connection == .byok {
                Picker("Provider", selection: $config.api.provider) {
                    ForEach(AIAPIProvider.allCases) { Text($0.title).tag($0) }
                }.onChange(of: config.api.provider) { _, provider in
                    config.api.endpoint = provider.endpoint; config.api.model = ""; keyDraft = ""; discovery.cancel(); persist()
                }
            }
            if config.http.provider == .compatible {
                TextField("API base URL", text: httpBinding.endpoint, prompt: Text("https://"))
                    .onSubmit { discovery.cancel(); keyDraft = ""; persist() }
            }
            TextField("Model ID", text: httpBinding.model, prompt: Text("Model name")).onSubmit { persist() }
            if !discovery.models.isEmpty {
                Picker("Available models", selection: httpBinding.model) {
                    Text("Choose a model…").tag("")
                    if !config.http.model.isEmpty && !discovery.models.contains(config.http.model) { Text(config.http.model).tag(config.http.model) }
                    ForEach(discovery.models, id: \.self) { Text($0).tag($0) }
                }.onChange(of: config.http.model) { _, _ in persist() }
            }
            SecureField(config.connection == .local ? "API key (optional)" : "API key", text: $keyDraft, prompt: Text("Paste a key to save it"))
            LabeledContent {
                Button("Save Key") { saveKey() }.disabled(keyDraft.isEmpty || !loaded)
                Button("Remove Key") { removeKey() }.disabled(!loaded)
                Button("Test Connection") { testConnection() }.disabled(discovery.loading || !loaded)
            } label: {
                HStack(spacing: 6) {
                    if discovery.loading { ProgressView().controlSize(.small) }
                    if let message = discovery.message { Text(message).foregroundStyle(.secondary) }
                }
            }
        } header: {
            Text(config.connection == .byok ? "Bring Your Own Key" : "Model")
        } footer: {
            SettingsFooter(config.connection == .byok
                 ? "Uses your API account and its billing. Keys stay in macOS Keychain and are excluded from configuration backups. Text chat only: no filesystem, terminal or other agent tools."
                 : "Text chat only: no filesystem, terminal or other agent tools.")
        }
        .disabled(!loaded)
    }
    private var localServers: some View {
        Section {
            if discovery.servers.isEmpty { Text("No servers found yet.").foregroundStyle(.secondary) }
            ForEach(discovery.servers) { server in
                LabeledContent {
                    if !server.models.isEmpty {
                        Button("Use") {
                            config.localAPI = server.configuration; config.localAPI.model = server.models[0]
                            discovery.select(server); keyDraft = ""; persist()
                        }.background(ControlAnchor("settings.use-server"))
                    }
                } label: {
                    Text(server.name)
                    Text(server.message)
                }
            }
        } header: {
            HStack {
                Text("Local Model Servers")
                Spacer()
                Button("Scan Again") { discovery.discover() }.controlSize(.small).font(.callout)
            }
        } footer: {
            SettingsFooter("Connects to a model server already running on this Mac. Detection lists available models; it does not load or download them.")
        }
    }
    private func saveKey() {
        do {
            try config.http.validate(requireModel: false)
            guard persist() else { return }
            try credentials.write(config.http.credentialID, keyDraft)
            keyDraft = ""; report("API key saved in Keychain", failure: false)
        } catch { report((error as? LocalizedError)?.errorDescription ?? "Couldn’t save the API key.", failure: true) }
    }
    private func removeKey() {
        do { guard persist() else { return }; try credentials.write(config.http.credentialID, nil); keyDraft = ""; report("API key removed", failure: false) }
        catch { report("Couldn’t remove the API key from Keychain.", failure: true) }
    }
    private func testConnection() {
        do {
            guard keyDraft.isEmpty else { report("Save your key before testing the connection.", failure: true); return }
            guard persist() else { return }
            discovery.refresh(config.http, key: try credentials.read(config.http.credentialID) ?? "")
        } catch { report("Couldn’t read the API key from Keychain.", failure: true) }
    }
    @discardableResult private func persist() -> Bool {
        guard loaded else { return false }
        do {
            guard try AIConfiguration.load(at: configURL) == saved else {
                report("AI settings changed elsewhere. Reopen this section before editing again.", failure: true); return false
            }
            if config == saved { return true }
            try config.save(at: configURL, expected: saved); saved = config; onChange()
            report("Settings saved", failure: false); return true
        } catch { report("Couldn’t save AI settings. Your edits remain here; try again.", failure: true); return false }
    }
    private func report(_ text: String, failure: Bool) { feedback = text; failed = failure }
}
