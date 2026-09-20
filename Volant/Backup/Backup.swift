import AppKit
import VolantCore

/// Panels and alerts for export and import. What an import would change is resolved by
/// `BackupFolder` so it can be tested without a file picker; this layer only collects the folder,
/// shows the summary, and reports failures.
enum Backup {
    static func export() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true; panel.canChooseFiles = false; panel.canCreateDirectories = true
        panel.prompt = "Export Here"; panel.message = "Choose a folder. Volant will create a dated backup folder inside it."
        guard panel.runModal() == .OK, let base = panel.url else { return }
        let dest = base.appendingPathComponent(BackupFolder.exportName(), isDirectory: true)
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
        let notesDestination = Preferences.supportDirectory.appendingPathComponent("Notes", isDirectory: true)
        let plan: BackupPlan
        do {
            plan = try BackupFolder.plan(source: src, notesDestination: notesDestination)
        } catch {
            alert("Import failed", error.localizedDescription); return false
        }
        let confirm = NSAlert()
        confirm.messageText = "Import this backup?"
        confirm.informativeText = summary(for: plan)
        confirm.addButton(withTitle: "Import"); confirm.addButton(withTitle: "Cancel")
        guard confirm.runModal() == .alertFirstButtonReturn else { return false }
        do {
            try BackupFolder.apply(plan, source: src, configURL: Preferences.configURL, notesDestination: notesDestination)
            return true
        } catch {
            alert("Import failed", error.localizedDescription); return false
        }
    }

    private static func summary(for plan: BackupPlan) -> String {
        let incoming = plan.preferences
        var summary = "Summon: \(KeyCombo.display(incoming.summonHotKey))\nNotes: \(KeyCombo.display(incoming.notesHotKey))\n"
        summary += "App hotkeys: " + (incoming.appHotKeys.isEmpty ? "none" : incoming.appHotKeys.map { "\(KeyCombo.display($0.hotKey)) → \($0.bundleIdentifier)" }.joined(separator: ", ")) + "\n"
        summary += "Quicklinks: " + (incoming.quicklinks.isEmpty ? "none" : incoming.quicklinks.map { "\($0.name) → \($0.url)" }.joined(separator: ", ")) + "\n"
        summary += "Snippets: \(incoming.snippets.count)   Aliases: \(incoming.aliases.count)\n"
        summary += "Notes to add: \(plan.notes.count) (existing notes are kept)"
        return ([summary] + plan.report).joined(separator: "\n")
    }

    private static func alert(_ title: String, _ text: String) {
        let a = NSAlert(); a.messageText = title; a.informativeText = text; a.runModal()
    }
}
