import SwiftUI

/// Settings › Dictation Keyboard: whether the optional Volant keyboard is set up, the walkthrough
/// that adds it, how long the microphone stays open after a dictation, and filler removal.
/// `-fixtureKeyboardSetup YES` opens it on launch for simulator review, and
/// `-fixtureKeyboardSetupPage 0|1|2` opens the walkthrough at that page.
struct KeyboardSetupView: View {
    @EnvironmentObject private var mac: MacSettings
    @ObservedObject private var service = DictationService.shared
    @AppStorage(DictationService.microphoneMinutesKey) private var microphoneMinutes = 5
    @AppStorage(KeyboardDictationSettings.removesFillersKey, store: KeyboardDictationSettings.defaults) private var removesFillers = true
    @AppStorage(KeyboardDictationSettings.recordsInKeyboardKey, store: KeyboardDictationSettings.defaults) private var recordsInKeyboard = true
    @AppStorage(KeyboardDictationSettings.formatsSpokenTextKey, store: KeyboardDictationSettings.defaults) private var formatsSpokenText = true
    @State private var walkthrough: KeyboardSetupFlow.Page?

    var body: some View {
        List {
            Section {
                VStack(spacing: 16) {
                    KeyboardPreview()
                    Button {
                        walkthrough = .intro
                    } label: {
                        Text(KeyboardPresence.lastSeen == nil ? "Set Up Keyboard" : "Walk Through Setup Again")
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
                Text("An optional keyboard for Volant's dictation. Type on the Apple keyboard as usual and switch with the globe key when you want to dictate.")
            }

            Section {
                Picker(selection: $microphoneMinutes) {
                    ForEach(DictationService.microphoneMinuteChoices, id: \.self) { minutes in
                        Text(label(for: minutes)).tag(minutes)
                    }
                } label: {
                    SettingsRow(symbol: "mic", title: "Keep Microphone Open", value: nil)
                }
                Toggle(isOn: $removesFillers) {
                    SettingsRow(symbol: "text.badge.minus", title: "Remove Filler Words", value: nil)
                }
                Toggle(isOn: $formatsSpokenText) {
                    VStack(alignment: .leading, spacing: 2) {
                        SettingsRow(symbol: "textformat.123", title: "Format Numbers, Punctuation and Lists", value: nil)
                        Text("Writes “twenty five” as 25 and “comma” as a comma, and turns “first… second…” or “new line” into lines.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Toggle(isOn: $recordsInKeyboard) {
                    SettingsRow(symbol: "waveform", title: "Record in Keyboard (Experimental)", value: nil)
                }
                if recordsInKeyboard, let result = lastRecordResult {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(result.ok ? "Last recorded in the keyboard \(result.date.formatted(.relative(presentation: .named)))"
                                       : "Last fell back to Volant \(result.date.formatted(.relative(presentation: .named)))")
                            .font(.subheadline)
                        if !result.ok, !result.reason.isEmpty {
                            Text(result.reason).font(.caption).foregroundStyle(.secondary)
                        }
                        if let lastDictation {
                            Text(lastDictation).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
                if service.microphoneIsOpen {
                    Button(role: .destructive) { service.closeMicrophone() } label: {
                        SettingsRow(symbol: "mic.slash", title: "Close Microphone Now", value: nil)
                    }
                    .buttonStyle(.row)
                }
            } header: {
                Text("Dictation")
            } footer: {
                Text(dictationFooter)
            }
        }
        .navigationTitle("Dictation Keyboard")
        .navigationBarTitleDisplayMode(.inline)
        .fullScreenCover(item: $walkthrough) { page in
            KeyboardSetupFlow(page: page)
        }
        .task {
            guard let page = UserDefaults.standard.string(forKey: "fixtureKeyboardSetupPage").flatMap(Int.init) else { return }
            try? await Task.sleep(for: .milliseconds(500))
            walkthrough = KeyboardSetupFlow.Page(rawValue: page)
        }
    }

    /// How the keyboard's last in-keyboard recording went, as it noted in the App Group.
    private var lastRecordResult: (date: Date, ok: Bool, reason: String)? {
        guard let result = KeyboardDictationSettings.defaults?.dictionary(forKey: KeyboardDictationSettings.recordResultKey),
              let date = result["date"] as? Date, let ok = result["ok"] as? Bool else { return nil }
        return (date, ok, result["reason"] as? String ?? "")
    }

    /// The keyboard's last in-keyboard dictation, for telling apart why one produced nothing.
    private var lastDictation: String? {
        guard let entry = KeyboardDictationLog.read() else { return nil }
        let seconds = Int(entry.duration.rounded())
        let length = String(format: "%d:%02d", seconds / 60, seconds % 60)
        return String(localized: "Last in-keyboard dictation \(entry.started.formatted(.relative(presentation: .named))): \(length) long, \(entry.chunks) audio chunks, \(entry.characters) characters heard; \(entry.outcome ?? String(localized: "still running"))")
    }

    private var status: String {
        guard let seen = KeyboardPresence.lastSeen else { return String(localized: "Not Set Up") }
        return String(localized: "Used \(seen.formatted(.relative(presentation: .named)))")
    }

    private func label(for minutes: Int) -> String {
        minutes == 0 ? String(localized: "Close Right Away") : String(localized: "\(minutes) min")
    }

    private var dictationFooter: String {
        let microphone = String(localized: "Record in Keyboard listens without leaving the app you're typing in. It relies on a technique Apple hasn't documented, so if it can't start, the keyboard switches to Volant to listen instead. When Volant listens, keeping the microphone open lets the next dictation start without switching again; iOS shows the orange microphone indicator while it is open, and nothing is heard or kept between dictations.")
        guard mac.vocabularyCount > 0 else { return microphone }
        return microphone + " " + String(localized: "Uses the \(mac.vocabularyCount) vocabulary words you added in Volant on your Mac.")
    }
}

extension KeyboardSetupFlow.Page: Identifiable {
    var id: Int { rawValue }
}
