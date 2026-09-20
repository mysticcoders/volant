import AppKit
import VolantCore

/// Export and import of config and notes to a folder the user picks. Clipboard history is excluded by design:
/// it is encrypted under this Mac's Keychain key. Import previews hotkeys and quicklinks before applying.
enum Backup {
    static func export() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true; panel.canChooseFiles = false; panel.canCreateDirectories = true
        panel.prompt = "Export Here"; panel.message = "Choose a folder. Volant will create a dated backup folder inside it."
        guard panel.runModal() == .OK, let base = panel.url else { return }
        let stamp = Date().formatted(.iso8601.year().month().day())
        let dest = base.appendingPathComponent("Volant-Backup-\(stamp)", isDirectory: true)
        let fm = FileManager.default
        do {
            try fm.createDirectory(at: dest, withIntermediateDirectories: true)
            try? fm.removeItem(at: dest.appendingPathComponent("config.json"))
            try fm.copyItem(at: Preferences.configURL, to: dest.appendingPathComponent("config.json"))
            let notes = Preferences.supportDirectory.appendingPathComponent("Notes")
            if fm.fileExists(atPath: notes.path) {
                try? fm.removeItem(at: dest.appendingPathComponent("Notes"))
                try fm.copyItem(at: notes, to: dest.appendingPathComponent("Notes"))
            }
            NSWorkspace.shared.activateFileViewerSelecting([dest])
        } catch {
            alert("Export failed", error.localizedDescription)
        }
    }

    /// Returns true if something was imported and the app should reload its config.
    static func importBackup() -> Bool {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true; panel.canChooseFiles = false
        panel.prompt = "Import"; panel.message = "Choose a Volant-Backup or Vey-Backup folder."
        guard panel.runModal() == .OK, let src = panel.url else { return false }
        let configURL = src.appendingPathComponent("config.json")
        let notesURL = src.appendingPathComponent("Notes")
        guard let data = try? Data(contentsOf: configURL), let incoming = try? JSONDecoder().decode(Preferences.self, from: data) else {
            alert("Import failed", "No readable config.json in that folder."); return false
        }
        var summary = "Summon: \(KeyCombo.display(incoming.summonHotKey))\nNotes: \(KeyCombo.display(incoming.notesHotKey))\n"
        summary += "App hotkeys: " + (incoming.appHotKeys.isEmpty ? "none" : incoming.appHotKeys.map { "\(KeyCombo.display($0.hotKey)) → \($0.bundleIdentifier)" }.joined(separator: ", ")) + "\n"
        summary += "Quicklinks: " + (incoming.quicklinks.isEmpty ? "none" : incoming.quicklinks.map { "\($0.name) → \($0.url)" }.joined(separator: ", ")) + "\n"
        summary += "Snippets: \(incoming.snippets.count)   Aliases: \(incoming.aliases.count)\n"
        let noteCount = (try? FileManager.default.contentsOfDirectory(atPath: notesURL.path))?.filter { $0.hasSuffix(".md") }.count ?? 0
        summary += "Notes to add: \(noteCount) (existing notes are kept)"
        let confirm = NSAlert()
        confirm.messageText = "Import this backup?"
        confirm.informativeText = summary
        confirm.addButton(withTitle: "Import"); confirm.addButton(withTitle: "Cancel")
        guard confirm.runModal() == .alertFirstButtonReturn else { return false }
        let fm = FileManager.default
        do {
            try data.write(to: Preferences.configURL, options: .atomic)
            if noteCount > 0 {
                let dest = Preferences.supportDirectory.appendingPathComponent("Notes", isDirectory: true)
                try fm.createDirectory(at: dest, withIntermediateDirectories: true)
                for name in try fm.contentsOfDirectory(atPath: notesURL.path) where name.hasSuffix(".md") {
                    var target = dest.appendingPathComponent(name)
                    if fm.fileExists(atPath: target.path) { target = dest.appendingPathComponent("imported-\(name)") }
                    try fm.copyItem(at: notesURL.appendingPathComponent(name), to: target)
                }
            }
            return true
        } catch {
            alert("Import failed", error.localizedDescription); return false
        }
    }

    private static func alert(_ title: String, _ text: String) {
        let a = NSAlert(); a.messageText = title; a.informativeText = text; a.runModal()
    }
}
