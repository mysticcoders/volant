import SwiftUI

/// Settings › Dictation Keyboard: the keyboard's preview and setup, the dictation switches, and
/// links to the speech model and the advanced recording options. Kept to labels; the details live
/// one level down. `-fixtureKeyboardSetup YES` opens it on launch for simulator review, and
/// `-fixtureKeyboardSetupPage 0|1|2` opens the walkthrough at that page.
struct KeyboardSetupView: View {
    @EnvironmentObject private var mac: MacSettings
    @AppStorage(KeyboardDictationSettings.removesFillersKey, store: KeyboardDictationSettings.defaults) private var removesFillers = true
    @AppStorage(KeyboardDictationSettings.formatsSpokenTextKey, store: KeyboardDictationSettings.defaults) private var formatsSpokenText = true
    @AppStorage(KeyboardDictationSettings.cleansUpKey, store: KeyboardDictationSettings.defaults) private var cleansUp = false
    @AppStorage(ParakeetModel.enabledKey, store: KeyboardDictationSettings.defaults) private var usesParakeet = false
    @State private var walkthrough: KeyboardSetupFlow.Page?
    @State private var install = KeyboardInstall.current
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        List {
            Section {
                VStack(spacing: 16) {
                    KeyboardPreview()
                    Button {
                        walkthrough = install.isReady ? .tryIt : .intro
                    } label: {
                        Text(install.isReady ? "Try It" : "Set Up Keyboard")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 4)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                }
                .listRowInsets(EdgeInsets(top: 12, leading: 12, bottom: 12, trailing: 12))
                SettingsRow(symbol: "keyboard", title: "Volant Keyboard", value: status)
            } footer: {
                Text("Switch to it with the globe key when you want to dictate.")
            }

            Section("Dictation") {
                NavigationLink {
                    SpeechModelView()
                } label: {
                    SettingsRow(symbol: "waveform", title: "Speech Model", value: usesParakeet ? "Parakeet" : "Apple")
                }
                Toggle(isOn: $removesFillers) {
                    SettingsRow(symbol: "text.badge.minus", title: "Remove Filler Words", value: nil)
                }
                Toggle(isOn: $formatsSpokenText) {
                    SettingsRow(symbol: "textformat.123", title: "Smart Formatting", value: nil)
                }
                Toggle(isOn: $cleansUp) {
                    VStack(alignment: .leading, spacing: 2) {
                        SettingsRow(symbol: "apple.intelligence", title: "Apple Intelligence Cleanup", value: nil)
                        if let reason = DictationAppleIntelligenceCleanup.unavailableReason {
                            Text(reason).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
                .disabled(DictationAppleIntelligenceCleanup.unavailableReason != nil && !cleansUp)
                if mac.vocabularyCount > 0 {
                    SettingsRow(symbol: "character.book.closed", title: "Vocabulary",
                                value: String(localized: "\(mac.vocabularyCount) words from Mac"))
                }
            }

            Section {
                NavigationLink {
                    KeyboardAdvancedView()
                } label: {
                    SettingsRow(symbol: "slider.horizontal.3", title: "Advanced", value: nil)
                }
            }
        }
        .navigationTitle("Dictation Keyboard")
        .navigationBarTitleDisplayMode(.inline)
        .fullScreenCover(item: $walkthrough, onDismiss: { install = KeyboardInstall.current }) { page in
            KeyboardSetupFlow(page: page)
        }
        .onAppear { install = KeyboardInstall.current }
        .onChange(of: scenePhase) { _, phase in if phase == .active { install = KeyboardInstall.current } }
        .task {
            guard let page = UserDefaults.standard.string(forKey: "fixtureKeyboardSetupPage").flatMap(Int.init) else { return }
            try? await Task.sleep(for: .milliseconds(500))
            walkthrough = KeyboardSetupFlow.Page(rawValue: page)
        }
    }

    private var status: String {
        if install.isReady { return String(localized: "Ready") }
        if install.fullAccessKnownOff { return String(localized: "Needs Full Access") }
        return install.isAdded ? String(localized: "Added") : String(localized: "Not Set Up")
    }
}

/// Settings › Dictation Keyboard › Advanced: how the keyboard records, how long Volant keeps the
/// microphone open when it listens instead, and what happened in the last dictation.
struct KeyboardAdvancedView: View {
    @ObservedObject private var service = DictationService.shared
    @AppStorage(DictationService.microphoneMinutesKey) private var microphoneMinutes = 5
    @AppStorage(KeyboardDictationSettings.recordsInKeyboardKey, store: KeyboardDictationSettings.defaults) private var recordsInKeyboard = true

    var body: some View {
        List {
            Section {
                Toggle(isOn: $recordsInKeyboard) {
                    SettingsRow(symbol: "keyboard", title: "Record in Keyboard", value: nil)
                }
                Picker(selection: $microphoneMinutes) {
                    ForEach(DictationService.microphoneMinuteChoices, id: \.self) { minutes in
                        Text(label(for: minutes)).tag(minutes)
                    }
                } label: {
                    SettingsRow(symbol: "mic", title: "Keep Microphone Open", value: nil)
                }
                if service.microphoneIsOpen {
                    Button(role: .destructive) { service.closeMicrophone() } label: {
                        SettingsRow(symbol: "mic.slash", title: "Close Microphone Now", value: nil)
                    }
                    .buttonStyle(.row)
                }
            } footer: {
                Text("When the keyboard can't record, Volant opens to listen and can keep the microphone open for the next dictation.")
            }

            if let entry = KeyboardDictationLog.read() {
                Section("Last Dictation") {
                    LabeledContent("When", value: entry.started.formatted(.relative(presentation: .named)))
                    LabeledContent("Length", value: Self.length(entry.duration))
                    if let outcome = entry.outcome {
                        Text(outcome).font(.footnote).foregroundStyle(.secondary)
                    }
                    if let fallback = fallbackReason {
                        Text("Recorded in Volant: \(fallback)").font(.footnote).foregroundStyle(.secondary)
                    }
                }
            }
        }
        .navigationTitle("Advanced")
        .navigationBarTitleDisplayMode(.inline)
    }

    /// Why the keyboard last had to record in Volant, when that is its most recent attempt.
    private var fallbackReason: String? {
        guard let result = KeyboardDictationSettings.defaults?.dictionary(forKey: KeyboardDictationSettings.recordResultKey),
              result["ok"] as? Bool == false, let reason = result["reason"] as? String, !reason.isEmpty else { return nil }
        return reason
    }

    private func label(for minutes: Int) -> String {
        minutes == 0 ? String(localized: "Off") : String(localized: "\(minutes) min")
    }

    private static func length(_ duration: TimeInterval) -> String {
        let seconds = Int(duration.rounded())
        return String(format: "%d:%02d", seconds / 60, seconds % 60)
    }
}

extension KeyboardSetupFlow.Page: Identifiable {
    var id: Int { rawValue }
}
