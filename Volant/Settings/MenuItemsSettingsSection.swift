import SwiftUI
import VolantCore

/// Settings › General › Search Menu Items: the opt-in switch, what turning it on lets Volant do,
/// and the Accessibility state while it is on.
struct MenuItemsSettingsSection: View {
    let config: Preferences
    @ObservedObject var access: MenuItemsAccess
    let apply: (() throws -> Void) -> Void
    let configURL: URL

    var body: some View {
        Section {
            Toggle(isOn: Binding(get: { config.searchMenuItems }, set: choose)) {
                Text("Search Menu Items")
                Text("Type menus in the launcher to search the menu bar of the app you were using, then press Return to choose an item.")
            }
            .accessibilityIdentifier("settings-search-menu-items")
            if config.searchMenuItems {
                LabeledContent("Accessibility") { MenuItemsAccessStatus(access: access) }
            } else if access.stoppedHelper {
                LabeledContent {
                    Button("Open Accessibility Settings") { DictationTypingAccess.openAccessibilitySettings() }
                } label: {
                    Text("Volant no longer uses Accessibility. To remove its access, turn off Volant in Privacy & Security → Accessibility.")
                        .foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
            }
        } header: {
            Text("Menu Items")
        } footer: {
            SettingsFooter(String(localized: "When you run the command, Volant’s input helper reads the menu titles of the app in front and presses the item you choose. It uses the same Volant permission in Privacy & Security → Accessibility as Type at the cursor. Menu titles can include document names, so they stay in memory only while the launcher is open and are never saved, synced or logged. Volant never presses items in the Apple menu."))
        }
        .onAppear { access.refresh(config.searchMenuItems) }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            access.refresh(config.searchMenuItems)
        }
    }

    /// Saves the choice, then lets the access model prompt once or stop the helper.
    private func choose(_ enabled: Bool) {
        guard enabled != config.searchMenuItems else { return }
        var saved = false
        apply {
            try Preferences.updateBoolean("searchMenuItems", value: enabled, at: configURL)
            saved = true
        }
        if saved { access.chose(enabled) }
    }
}

/// The Accessibility state for Search Menu Items, with the action that fixes it.
struct MenuItemsAccessStatus: View {
    @ObservedObject var access: MenuItemsAccess

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
                Button("Open Accessibility Settings") { DictationTypingAccess.openAccessibilitySettings() }
            case .unavailable:
                Text("Input helper unavailable").foregroundStyle(.secondary)
                Button("Check Again") { access.refresh(true) }
            }
        }
    }
}
