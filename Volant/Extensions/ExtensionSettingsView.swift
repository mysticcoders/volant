import SwiftUI

struct ExtensionSettingsView: View {
    let configURL: URL
    let onChange: () -> Void
    @State private var installed: [InstalledExtension] = []
    @State private var problems: [String] = []
    @State private var error: String?
    private var manager: ExtensionManager { ExtensionManager(configURL: configURL) }
    private func reload() {
        let manager = manager; manager.reload()
        installed = manager.extensions; problems = manager.loadErrors
    }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Extensions start off. Enable one here or choose Enable and Run the first time you use it.")
                    .font(.callout).foregroundStyle(.secondary)
                Text("Try the bundled example: ext hello Andrew").font(.callout)
                HStack {
                    Button("Open Extensions Folder") { NSWorkspace.shared.open(ExtensionManager.directory) }
                    Button("Refresh", action: reload)
                }
                if installed.isEmpty { Text("No extensions installed.").foregroundStyle(.secondary) }
                ForEach(installed) { ext in
                    VStack(alignment: .leading, spacing: 6) {
                        Toggle(ext.name, isOn: Binding(get: { ext.enabled }, set: { enabled in
                            do { try manager.setEnabled(ext, enabled); reload(); onChange() }
                            catch { self.error = error.localizedDescription; reload() }
                        })).accessibilityIdentifier("extension-toggle-" + ext.id)
                        Text(ext.accessDescription).font(.callout).foregroundStyle(.secondary)
                        Text("Version \(ext.manifest.version)")
                            .font(.caption).foregroundStyle(.secondary)
                    }.padding(12).frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
                }
                ForEach(problems, id: \.self) { Text($0).font(.callout).foregroundStyle(.secondary) }
                Text("Changed code or permissions require enabling again. Extensions run only when you invoke them.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .onAppear(perform: reload)
        .alert("Couldn’t change extension", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
            Button("OK") { error = nil }
        } message: { Text(error ?? "") }
    }
}

struct ExtensionPermissionRequest: Identifiable {
    let id = UUID()
    let extensionItem: InstalledExtension
    let input: String
}

struct ExtensionPermissionView: View {
    let request: ExtensionPermissionRequest
    let enable: () -> Void
    let cancel: () -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Enable \(request.extensionItem.name)?").font(.title2.bold())
            Text(request.extensionItem.accessDescription)
            Text("This extension will run now and stay enabled. You can turn it off in Settings → Extensions.")
                .font(.callout).foregroundStyle(.secondary)
            HStack {
                Spacer()
                Button("Cancel", action: cancel).keyboardShortcut(.cancelAction)
                Button("Enable and Run", action: enable).keyboardShortcut(.defaultAction)
            }
        }.padding(24).frame(width: 390)
            .background(Color(nsColor: .windowBackgroundColor))
    }
}
