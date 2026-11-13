import SwiftUI
import VolantCore

/// Focus settings in General: how long Snooze lets a blocked app or site through. The block list
/// itself is edited where sessions start, in the launcher's Focus form.
struct FocusSettingsSection: View {
    let config: Preferences
    let configURL: URL
    let apply: (() throws -> Void) -> Void

    var body: some View {
        Section {
            Stepper(value: Binding(get: { config.focus.snoozeMinutes }, set: save), in: FocusPreferences.snoozeRange) {
                Text("Snooze for \(config.focus.snoozeMinutes, specifier: "%lld") minutes", comment: "Focus setting: how long Snooze allows a blocked app or website")
                Text("How long Snooze lets a blocked app or website through. Three minutes is usually enough.", comment: "Focus setting description")
            }
            .accessibilityIdentifier("settings-focus-snooze")
        } header: {
            Text("Focus", comment: "Settings section header")
        } footer: {
            SettingsFooter(String(localized: "Type focus in the launcher to start a session. Blocked apps are hidden, never quit. Set a Toggle Focus Session shortcut in Keyboard Shortcuts.", comment: "Focus settings footer; focus is a typed command and stays in English"))
        }
    }

    /// Saves the snooze length against the settings this view shows, so a stale copy is refused.
    private func save(_ minutes: Int) {
        guard minutes != config.focus.snoozeMinutes else { return }
        var updated = config.focus
        updated.snoozeMinutes = minutes
        apply { try Preferences.updateFocus(updated, expected: config.focus, at: configURL) }
    }
}
