import AppKit
import SwiftUI

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
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Picker("Connection", selection: $config.connection) {
                    ForEach(AIConnectionKind.allCases) { Text($0.title).tag($0) }
                }.pickerStyle(.segmented).disabled(!loaded)
                    .onChange(of: config.connection) { _, kind in
                        keyDraft = ""; discovery.cancel(); persist()
                        if kind == .local { discovery.discover() }
                    }
                if config.connection == .acp { acpControls }
                else { apiControls }
                if model.active {
                    Text("Current conversation: \(model.providerTitle). Settings apply to the next conversation.").font(.callout).foregroundStyle(.secondary)
                    Button("Open Current Conversation") { openConversation(config) }
                } else {
                    Button(config.connection == .acp ? "Connect ACP" : "Open AI Chat") {
                        if persist() { openConversation(config) }
                    }.disabled(!config.isConfigured || !loaded)
                }
                if let feedback {
                    Text(feedback).font(.callout).foregroundStyle(failed ? Color.red : Color.secondary).accessibilityLabel(feedback)
                }
            }.frame(maxWidth: .infinity, alignment: .leading)
        }
        .onAppear {
            do {
                config = try AIConfiguration.load(at: configURL); saved = config; loaded = true
                if config.connection == .local { discovery.discover() }
            } catch { report("Couldn’t load AI settings. Fix or reload the configuration before editing.", failure: true) }
        }
        .onChange(of: config.http.endpoint) { _, _ in discovery.endpointChanged(config.http.endpoint); keyDraft = "" }
        .onDisappear { discovery.cancel(); keyDraft = ""; if loaded && config != saved { persist() } }
    }
    private var acpControls: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("ACP connections").font(.headline)
            Picker("Provider", selection: $config.provider) {
                Text("Choose a provider…").tag("")
                ForEach(ACPProvider.allCases) { Text($0.title).tag($0.rawValue) }
            }.disabled(!loaded).onChange(of: config.provider) { _, _ in persist() }
            Text("Uses your agent’s existing CLI login. Sign in with that provider before connecting.").foregroundStyle(.secondary)
            HStack {
                Text(config.project.isEmpty ? "General chat (no project)" : URL(fileURLWithPath: config.project).lastPathComponent)
                    .lineLimit(1).help(config.project)
                Spacer()
                Button("Choose Folder…") { chooseProject { url in if let url { config.project = url.path; persist() } } }.disabled(!loaded)
            }
            if !config.project.isEmpty { Button("Use General Chat") { config.project = ""; persist() } }
            Text("A working folder is optional. General chat uses Volant’s own folder. Your agent’s permissions still control tool access.").font(.callout).foregroundStyle(.secondary)
        }
    }
    private var httpBinding: Binding<AIHTTPConfiguration> {
        Binding(get: { config.http }, set: { if config.connection == .local { config.localAPI = $0 } else { config.api = $0 } })
    }
    private var apiControls: some View {
        VStack(alignment: .leading, spacing: 12) {
            if config.connection == .byok {
                Text("Bring your own key").font(.headline)
                Picker("Provider", selection: $config.api.provider) {
                    ForEach(AIAPIProvider.allCases) { Text($0.title).tag($0) }
                }.onChange(of: config.api.provider) { _, provider in
                    config.api.endpoint = provider.endpoint; config.api.model = ""; keyDraft = ""; discovery.cancel(); persist()
                }
                Text("Uses your API account and its billing. Keys stay in macOS Keychain and are excluded from configuration backups.")
                    .font(.callout).foregroundStyle(.secondary)
            } else {
                localServers
                Text("Connects to a model server already running on this Mac. Detection lists available models; it does not load or download them.")
                    .font(.callout).foregroundStyle(.secondary)
            }
            if config.http.provider == .compatible {
                TextField("API base URL", text: httpBinding.endpoint).textFieldStyle(.roundedBorder)
                    .onSubmit { discovery.cancel(); keyDraft = ""; persist() }
            }
            TextField("Model ID", text: httpBinding.model).textFieldStyle(.roundedBorder).onSubmit { persist() }
            if !discovery.models.isEmpty {
                Picker("Available models", selection: httpBinding.model) {
                    Text("Choose a model…").tag("")
                    if !config.http.model.isEmpty && !discovery.models.contains(config.http.model) { Text(config.http.model).tag(config.http.model) }
                    ForEach(discovery.models, id: \.self) { Text($0).tag($0) }
                }.onChange(of: config.http.model) { _, _ in persist() }
            }
            SecureField(config.connection == .local ? "API key (optional)" : "API key", text: $keyDraft).textFieldStyle(.roundedBorder)
            HStack {
                Button("Save Key") { saveKey() }.disabled(keyDraft.isEmpty || !loaded)
                Button("Remove Key") { removeKey() }.disabled(!loaded)
                Spacer()
                if discovery.loading { ProgressView().controlSize(.small) }
                Button("Test Connection") { testConnection() }.disabled(discovery.loading || !loaded)
            }
            if let message = discovery.message { Text(message).font(.callout).foregroundStyle(.secondary) }
            Text("Text chat only. API connections do not get ACP’s filesystem, terminal or other agent tools.").font(.caption).foregroundStyle(.secondary)
        }.disabled(!loaded)
    }
    private var localServers: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack { Text("Local model servers").font(.headline); Spacer(); Button("Scan Again") { discovery.discover() } }
            ForEach(discovery.servers) { server in
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(server.name)
                        Spacer()
                        if !server.models.isEmpty {
                            Button("Use") {
                                config.localAPI = server.configuration; config.localAPI.model = server.models[0]
                                discovery.select(server); keyDraft = ""; persist()
                            }
                        }
                    }
                    Text(server.message).font(.caption).foregroundStyle(.secondary)
                }.padding(8).frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
            }
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
