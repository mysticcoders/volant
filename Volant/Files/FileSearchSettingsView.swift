import SwiftUI
import VolantCore

/// Settings → File Search: the optional fsearch integration. The switch only changes where
/// file results come from; Volant never installs or starts fsearch. The status line asks the running
/// daemon, through the agent helper, when the section appears or the switch changes.
struct FileSearchSettingsView: View {
    let config: Preferences
    let apply: (() throws -> Void) -> Void
    let configURL: URL
    var client = FSearchClient.shared
    @State private var status: String?

    var body: some View {
        Form {
            Section {
                Toggle(isOn: Binding(get: { config.fileSearchUsesFSearch }, set: { value in
                    apply { try Preferences.updateBoolean("fileSearchUsesFSearch", value: value, at: configURL) }
                    check()
                })) {
                    Text("Use fsearch for file search")
                    Text("Whole-disk results that tolerate typos, and filters such as ext:swift in / searches.")
                }.accessibilityIdentifier("settings.fsearch")
                LabeledContent("fsearch") {
                    Text(status ?? "Checking…").foregroundStyle(.secondary).multilineTextAlignment(.trailing)
                        .fixedSize(horizontal: false, vertical: true)
                }
            } footer: {
                SettingsFooter("Spotlight finds files in your home folder. fsearch is a separate tool you install and run yourself, with its own Full Disk Access. Whenever it isn’t running, Volant uses Spotlight.")
            }
        }
        .formStyle(.grouped)
        .onAppear(perform: check)
    }

    private func check() {
        status = nil
        client.status { result in
            switch result {
            case .success(let found):
                status = "Running · \(found.entries.formatted()) items" + (found.fullDiskAccess == false ? " · without Full Disk Access" : "")
            case .failure(let error):
                status = error.localizedDescription.replacingOccurrences(of: "fsearch: ", with: "")
            }
        }
    }
}
