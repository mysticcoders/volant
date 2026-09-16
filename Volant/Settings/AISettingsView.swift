import AppKit
import SwiftUI

struct AISettingsView: View {
    @ObservedObject var model: ACPModel
    let configURL: URL
    let onChange: () -> Void
    let openConversation: (AIConfiguration) -> Void
    let chooseProject: (@escaping (URL?) -> Void) -> Void
    @State private var config = AIConfiguration()
    @State private var saved = AIConfiguration()
    @State private var feedback: String?
    @State private var failed = false
    @State private var loaded = false
    var body: some View {
        ScrollView {
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
                    Button("Choose Folder…") {
                        chooseProject { url in if let url { config.project = url.path; persist() } }
                    }.disabled(!loaded)
                }
                if !config.project.isEmpty {
                    Button("Use General Chat") { config.project = ""; persist() }
                }
                Text("A working folder is optional. General chat uses Volant’s own folder. Your agent’s permissions still control tool access.").font(.callout).foregroundStyle(.secondary)
                if model.active {
                    Text("Current conversation: \(ACPProvider(rawValue: model.provider)?.title ?? model.provider). End it before switching connections.").font(.callout).foregroundStyle(.secondary)
                    Button("Open Current Conversation") { openConversation(config) }
                } else {
                    Button("Connect ACP") { if persist() { openConversation(config) } }.disabled(!config.isConfigured || !loaded)
                }
                if let feedback {
                    Text(feedback).font(.callout).foregroundStyle(failed ? Color.red : Color.secondary).accessibilityLabel(feedback)
                }
            }.frame(maxWidth: .infinity, alignment: .leading)
        }
        .onAppear {
            do { config = try AIConfiguration.load(at: configURL); saved = config; loaded = true }
            catch { report("Couldn’t load AI settings. Fix or reload the configuration before editing.", failure: true) }
        }
        .onDisappear { if loaded && config != saved { persist() } }
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
