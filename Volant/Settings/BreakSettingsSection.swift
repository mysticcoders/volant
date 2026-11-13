import SwiftUI
import VolantCore

/// Break settings in General: on or off, how work is counted, how often and how long breaks are,
/// how firmly they ask, and the heads-up. Each change is a narrow patch of `breaks` in config.json
/// against the settings this view shows, so a stale copy is refused.
struct BreakSettingsSection: View {
    let config: Preferences
    let configURL: URL
    let apply: (() throws -> Void) -> Void

    var body: some View {
        let breaks = config.breaks
        Section {
            Toggle(isOn: binding(\.enabled)) {
                Text("Remind me to take breaks", comment: "Breaks setting: turn break reminders on")
                Text("Volant covers the screen for a short break after a stretch of work.", comment: "Breaks setting description")
            }
            .accessibilityIdentifier("settings-breaks-enabled")
            Picker(selection: binding(\.mode)) {
                ForEach(BreakMode.allCases) { mode in Text(mode.title).tag(mode) }
            } label: {
                Text("Count", comment: "Breaks setting: how work time is counted")
                Text(breaks.mode == .activeTime
                     ? String(localized: "Only minutes you’re at the Mac count. Stepping away for a break’s length counts as a break.", comment: "Breaks setting description for Active Time")
                     : String(localized: "Breaks come on a fixed schedule, whatever you’re doing.", comment: "Breaks setting description for Clock Time"))
            }
            .accessibilityIdentifier("settings-breaks-mode")
            Stepper(value: binding(\.intervalMinutes), in: BreakPreferences.intervalRange, step: 5) {
                Text("Every \(breaks.intervalMinutes, specifier: "%lld") minutes", comment: "Breaks setting: minutes of work between breaks")
            }
            .accessibilityIdentifier("settings-breaks-interval")
            Stepper(value: binding(\.breakMinutes), in: BreakPreferences.lengthRange) {
                Text("Breaks last \(breaks.breakMinutes, specifier: "%lld") minutes", comment: "Breaks setting: how long each break lasts")
            }
            .accessibilityIdentifier("settings-breaks-length")
            Picker(selection: binding(\.strictness)) {
                ForEach(BreakStrictness.allCases) { strictness in Text(strictness.title).tag(strictness) }
            } label: {
                Text("Strictness", comment: "Breaks setting: how firmly a break asks the owner to step away")
                Text(description(breaks.strictness))
            }
            .accessibilityIdentifier("settings-breaks-strictness")
            Toggle(isOn: binding(\.headsUp)) {
                Text("Heads-up a minute before", comment: "Breaks setting: show a notice a minute before each break")
                Text("A small notice with Postpone and Skip.", comment: "Breaks setting description for the heads-up")
            }
            .accessibilityIdentifier("settings-breaks-heads-up")
        } header: {
            Text("Breaks", comment: "Settings section header")
        } footer: {
            SettingsFooter(String(localized: "Breaks wait while a camera or microphone is in use, and a running Focus session pauses during a break. Type break in the launcher to take one now, skip or pause.", comment: "Breaks settings footer; break is a typed command and stays in English"))
        }
    }

    private func description(_ strictness: BreakStrictness) -> String {
        switch strictness {
        case .gentle: return String(localized: "A reminder in the corner. The screen is never covered.", comment: "Breaks strictness description: Gentle")
        case .standard: return String(localized: "Covers every display, with Postpone and Skip.", comment: "Breaks strictness description: Standard")
        case .strict: return String(localized: "Covers every display. Skip appears after 10 seconds and must be held.", comment: "Breaks strictness description: Strict")
        }
    }

    /// A binding to one setting that saves only that change against the settings this view shows.
    private func binding<Value: Equatable>(_ keyPath: WritableKeyPath<BreakPreferences, Value>) -> Binding<Value> {
        Binding(get: { config.breaks[keyPath: keyPath] }, set: { value in
            guard value != config.breaks[keyPath: keyPath] else { return }
            var updated = config.breaks
            updated[keyPath: keyPath] = value
            let expected = config.breaks
            apply { try Preferences.updateBreaks(updated, expected: expected, at: configURL) }
        })
    }
}
