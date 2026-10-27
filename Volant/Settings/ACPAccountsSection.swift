import SwiftUI
import VolantCore

/// The account folders of one provider, and which of them its new conversations run under. A
/// conversation receives only the chosen folder's path, through the variable the provider reads;
/// signing in happens in the provider's own CLI.
struct ACPAccountsSection: View {
    @Binding var config: AIConfiguration
    let provider: ACPProvider
    let enabled: Bool
    let chooseFolder: (@escaping (URL?) -> Void) -> Void
    /// Saves `config` after a change.
    let save: () -> Void
    /// Reports why an account was not added.
    let refuse: (String) -> Void
    @State private var label = ""

    var body: some View {
        Section {
            LabeledContent("Account") {
                Picker("Account", selection: choice) {
                    Text("Default login").tag("")
                    ForEach(config.profiles(for: provider.rawValue)) { Text($0.label).tag($0.id) }
                }.labelsHidden().fixedSize()
            }.disabled(!enabled)
            ForEach(config.profiles(for: provider.rawValue)) { profile in
                LabeledContent {
                    Button("Remove") { config.removeProfile(id: profile.id); save() }.disabled(!enabled)
                        .help("Remove this account from Volant. Its folder and login stay.")
                } label: {
                    Text(profile.label)
                    Text(profile.directory).truncationMode(.middle).lineLimit(1).help(profile.directory)
                }
            }
            HStack {
                TextField("Add account", text: $label, prompt: Text("Label, such as Work")).textFieldStyle(.roundedBorder)
                Button("Choose Folder…", action: add).disabled(!enabled || ACPAccountProfile.trimmedLabel(label) == nil)
                    .background(ControlAnchor("settings.add-account"))
            }
        } header: {
            Text("Account")
        } footer: {
            SettingsFooter(footer)
        }
    }

    /// The default login is "", the picker's first tag.
    private var choice: Binding<String> {
        Binding(get: { config.account(for: provider.rawValue)?.id ?? "" },
                set: { config.chooseAccount($0, for: provider.rawValue); save() })
    }

    private func add() {
        guard let trimmed = ACPAccountProfile.trimmedLabel(label) else { return }
        chooseFolder { url in
            guard let url else { return }
            do {
                try config.addProfile(ACPAccountProfile(provider: provider.rawValue, label: trimmed, directory: url.path))
                label = ""
                save()
            } catch {
                refuse((error as? LocalizedError)?.errorDescription ?? String(localized: "Couldn’t add this account."))
            }
        }
    }

    private var footer: String {
        let variable = ACPAccountProfile.environmentKey(for: provider) ?? ""
        let title = provider.title
        if provider == .codex {
            let command = "CODEX_HOME=<folder> codex login"
            return String(localized: "To sign in to an account, open Terminal and run “\(command)”. New conversations run under the account chosen here, and each conversation keeps the account it started with. \(title) receives only the folder’s path, as \(variable); Volant never reads or copies what the folder holds. Default login starts \(title) without \(variable).", comment: "AI Settings account footer; the values are a Terminal command, the provider name and an environment variable")
        }
        let command = "CLAUDE_CONFIG_DIR=<folder> claude", login = "/login"
        return String(localized: "To sign in to an account, open Terminal and run “\(command)”, then enter “\(login)”. New conversations run under the account chosen here, and each conversation keeps the account it started with. \(title) receives only the folder’s path, as \(variable); Volant never reads or copies what the folder holds. Default login starts \(title) without \(variable).", comment: "AI Settings account footer; the values are a Terminal command, a command typed in it, the provider name and an environment variable")
    }
}
