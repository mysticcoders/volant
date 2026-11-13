import SwiftUI

/// Volant for iOS. Notes are plain Markdown files in the iCloud Drive container shared with the
/// Mac (local Documents/Notes when iCloud is off), styled with the Mac app's themes from
/// VolantCore. Writes are flushed when the app leaves the foreground and the folder is re-read on
/// return; while running, iCloud changes reload the list as they arrive.
@main
struct VolantMobileApp: App {
    @StateObject private var themes = ThemeStore()
    @StateObject private var mac = MacSettings()
    @State private var model: NotesModel?
    @State private var sync: NotesSync?
    @State private var bridge: ExtensionBridge?
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            ThemedRoot(store: themes) {
                if let model {
                    RootView(model: model, themes: themes)
                } else {
                    VolantMark(size: 64).frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .environmentObject(mac)
            .task { await start() }
            .onChange(of: scenePhase) { _, phase in
                switch phase {
                case .active:
                    model?.store.reload()
                    mac.refresh()
                    bridge?.importInbox()
                case .inactive, .background: model?.store.flush()
                @unknown default: break
                }
            }
        }
    }

    /// Picks the notes folder once, then builds the store and, for iCloud, the change watcher.
    private func start() async {
        guard model == nil else { return }
        VolantShortcuts.updateAppShortcutParameters()
        if let override = Self.notesDirectoryOverride {
            let model = NotesModel(store: NotesStore(directory: override), location: .init(directory: override, isICloud: false))
            self.model = model
            bridge = ExtensionBridge(model: model)
            return
        }
        let location = await NotesLocation.resolve()
        let store = NotesStore(directory: location.directory)
        let model = NotesModel(store: store, location: location)
        self.model = model
        bridge = ExtensionBridge(model: model)
        bridge?.importInbox()
        if location.isICloud {
            sync = NotesSync(directory: location.directory) { store.reload() }
        }
    }

    /// A notes folder passed as `-notesDirectory <path>`, used to launch against fixtures.
    private static var notesDirectoryOverride: URL? {
        UserDefaults.standard.string(forKey: "notesDirectory").map { URL(fileURLWithPath: $0, isDirectory: true) }
    }
}
