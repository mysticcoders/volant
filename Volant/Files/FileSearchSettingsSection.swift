import SwiftUI
import VolantCore

/// Settings → General → File Search: the optional fsearch integration. The switch only changes where
/// file results come from; Volant never installs or starts fsearch. The status line asks the running
/// daemon, through the agent helper, when the section appears or the switch changes.
struct FileSearchSettingsSection: View {
    let config: Preferences
    let apply: (() throws -> Void) -> Void
    let configURL: URL
    var client = FSearchClient.shared
    @State private var status: String?

    var body: some View {
        Section {
            Toggle("Use fsearch for file search", isOn: Binding(get: { config.fileSearchUsesFSearch }, set: { value in
                apply { try Preferences.updateBoolean("fileSearchUsesFSearch", value: value, at: configURL) }
                check()
            })).accessibilityIdentifier("settings.fsearch")
            LabeledContent("fsearch") {
                Text(status ?? "Checking…").foregroundStyle(.secondary).multilineTextAlignment(.trailing)
                    .fixedSize(horizontal: false, vertical: true)
            }
        } header: {
            Text("File Search")
        } footer: {
            SettingsFooter("Spotlight finds files in your home folder. With this on, file results come from fsearch instead: the whole disk, typos tolerated, and filters such as ext:swift in / searches. fsearch is a separate tool you install and run yourself, and it needs its own Full Disk Access to reach protected folders. When it isn’t running, Volant uses Spotlight.")
        }
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
