import AppKit
import VolantCore

/// Panels and alerts for export and import. What an import would change is resolved by
/// `BackupFolder` so it can be tested without a file picker; this layer only collects the folder,
/// shows the summary, and reports failures.
enum Backup {
    static func export() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true; panel.canChooseFiles = false; panel.canCreateDirectories = true
        panel.prompt = String(localized: "Export Here", comment: "Backup export folder picker button")
        panel.message = String(localized: "Choose a folder. Volant will create a dated backup folder inside it.", comment: "Backup export folder picker message")
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
            alert(String(localized: "Export failed", comment: "Backup alert title"), error.localizedDescription)
        }
    }

    /// Returns true if something was imported and the app should reload its config.
    static func importBackup() -> Bool {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true; panel.canChooseFiles = false
        panel.prompt = String(localized: "Import", comment: "Backup import folder picker button")
        panel.message = String(localized: "Choose a Volant-Backup folder.", comment: "Backup import folder picker message; Volant-Backup is the folder name and stays as is")
        guard panel.runModal() == .OK, let src = panel.url else { return false }
        let notesDestination = Preferences.supportDirectory.appendingPathComponent("Notes", isDirectory: true)
        let plan: BackupPlan
        do {
            plan = try BackupFolder.plan(source: src, notesDestination: notesDestination)
        } catch {
            alert(String(localized: "Import failed", comment: "Backup alert title"), error.localizedDescription); return false
        }
        let confirm = NSAlert()
        confirm.messageText = String(localized: "Import this backup?", comment: "Backup import confirmation title")
        confirm.informativeText = summary(for: plan)
        confirm.addButton(withTitle: String(localized: "Import", comment: "Backup import confirmation button")); confirm.addButton(withTitle: String(localized: "Cancel"))
        guard confirm.runModal() == .alertFirstButtonReturn else { return false }
        do {
            try BackupFolder.apply(plan, source: src, configURL: Preferences.configURL, notesDestination: notesDestination)
            return true
        } catch {
            alert(String(localized: "Import failed", comment: "Backup alert title"), error.localizedDescription); return false
        }
    }

    private static func summary(for plan: BackupPlan) -> String {
        let incoming = plan.preferences
        var summary = String(localized: "Summon: \(KeyCombo.display(incoming.summonHotKey))", comment: "Backup import summary line; the value is a key combination") + "\n"
            + String(localized: "Notes: \(KeyCombo.display(incoming.notesHotKey))", comment: "Backup import summary line; the value is the Open Notes key combination") + "\n"
        let appHotKeys = incoming.appHotKeys.map { "\(KeyCombo.display($0.hotKey)) → \($0.bundleIdentifier)" }.joined(separator: ", ")
        summary += (incoming.appHotKeys.isEmpty ? String(localized: "App hotkeys: none", comment: "Backup import summary line")
            : String(localized: "App hotkeys: \(appHotKeys)", comment: "Backup import summary line; the value lists key combinations and apps")) + "\n"
        let quicklinks = incoming.quicklinks.map { "\($0.name) → \($0.url)" }.joined(separator: ", ")
        summary += (incoming.quicklinks.isEmpty ? String(localized: "Quicklinks: none", comment: "Backup import summary line")
            : String(localized: "Quicklinks: \(quicklinks)", comment: "Backup import summary line; the value lists quicklink names and URLs")) + "\n"
        summary += String(localized: "Snippets: \(incoming.snippets.count)   Aliases: \(incoming.aliases.count)", comment: "Backup import summary line with counts") + "\n"
        summary += String(localized: "Notes to add: \(plan.notes.count) (existing notes are kept)", comment: "Backup import summary line")
        return ([summary] + plan.report).joined(separator: "\n")
    }

    private static func alert(_ title: String, _ text: String) {
        let a = NSAlert(); a.messageText = title; a.informativeText = text; a.runModal()
    }
}
