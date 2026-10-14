import SwiftUI
import VolantCore

/// Settings → Dictation: where dictation's text goes, when typing happens, the Accessibility state
/// while typing is chosen, and the cleanup, sound and volume options.
struct DictationSettingsView: View {
    let config: Preferences
    @ObservedObject var access: DictationTypingAccess
    let apply: (() throws -> Void) -> Void
    let configURL: URL

    var body: some View {
        Form {
            Section {
                Picker(selection: Binding(get: { config.dictationOutput }, set: choose)) {
                    Text("Copy to clipboard").tag(DictationOutput.copy)
                    Text("Type at the cursor").tag(DictationOutput.type)
                } label: {
                    Text("Dictation output")
                    Text(config.dictationOutput == .type ? "Types into the app you’re using." : "Copies what you said; press ⌘V to paste it.")
                }
                if config.dictationOutput == .type {
                    Picker("Type", selection: Binding(get: { config.dictationTypesWhileSpeaking }, set: { value in
                        apply { try Preferences.updateBoolean("dictationTypesWhileSpeaking", value: value, at: configURL) }
                    })) {
                        Text("While speaking").tag(true)
                        Text("When finished").tag(false)
                    }
                    LabeledContent("Accessibility") { DictationAccessStatus(access: access) }
                } else if access.stoppedHelper {
                    LabeledContent {
                        Button("Open Accessibility Settings") { access.openAccessibilitySettings() }
                    } label: {
                        Text("Volant no longer uses Accessibility. To remove its access, turn off Volant in Privacy & Security → Accessibility.")
                            .foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    }
                }
            } footer: {
                SettingsFooter(footer)
            }
            Section {
                Toggle(isOn: Binding(get: { config.dictationRemovesFillers }, set: { value in
                    apply { try Preferences.updateBoolean("dictationRemovesFillers", value: value, at: configURL) }
                })) {
                    Text("Remove filler words")
                    Text("Takes um, uh, er and hmm out of English dictation; words like “like” stay.")
                }
                Toggle("Play sounds when dictation starts and stops", isOn: Binding(get: { config.dictationPlaysSounds }, set: { value in
                    apply { try Preferences.updateBoolean("dictationPlaysSounds", value: value, at: configURL) }
                }))
                Toggle(isOn: Binding(get: { config.dictationLowersVolume }, set: { value in
                    apply { try Preferences.updateBoolean("dictationLowersVolume", value: value, at: configURL) }
                })) {
                    Text("Lower volume while dictating")
                    Text("Plays audio at a fifth of its volume while listening, then restores it unless you changed it.")
                }
            } header: {
                Text("While Dictating")
            }
        }
        .formStyle(.grouped)
        .onAppear { access.refresh(config.dictationOutput) }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            access.refresh(config.dictationOutput)
        }
    }

    /// Saves the choice, then lets the access model connect, prompt once, or stop the helper.
    private func choose(_ output: DictationOutput) {
        guard output != config.dictationOutput else { return }
        var saved = false
        apply {
            try Preferences.updateDictationOutput(output, at: configURL)
            saved = true
        }
        if saved { access.chose(output) }
    }

    private var footer: String {
        guard config.dictationOutput == .type else {
            return "Type at the cursor asks once for Accessibility permission."
        }
        return "Each phrase is typed as soon as it’s final, or everything when you stop. Return finishes and Escape cancels. Volant never types into password fields or while secure input is on, and copies instead. Only Volant’s input helper uses Accessibility; System Settings lists it as Volant."
    }
}

/// The Accessibility state for typing, with the action that fixes it.
struct DictationAccessStatus: View {
    @ObservedObject var access: DictationTypingAccess

    var body: some View {
        HStack(spacing: 8) {
            switch access.state {
            case .idle, .checking:
                ProgressView().controlSize(.small)
                Text("Checking…").foregroundStyle(.secondary)
            case .allowed:
                Label("Allowed", systemImage: "checkmark.circle.fill").foregroundStyle(.secondary)
            case .notAllowed:
                Text("Not allowed").foregroundStyle(.secondary)
                Button("Open Accessibility Settings") { access.openAccessibilitySettings() }
            case .unavailable:
                Text("Input helper unavailable").foregroundStyle(.secondary)
                Button("Check Again") { access.refresh(.type) }
            }
        }
    }
}
