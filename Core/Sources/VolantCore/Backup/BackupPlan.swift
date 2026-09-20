import Foundation

/// What an import would do, resolved before anything is written. The caller shows this for
/// confirmation and then applies it, so the decision and the file work can be tested apart from
/// the panels and alerts that collect them.
public struct BackupPlan {
    /// One note file to copy, with the name it will land under. Backup never replaces an existing
    /// note: a colliding name is resolved to a free one here rather than failing partway through.
    public struct NoteCopy: Equatable {
        public let source: String
        public let destination: String

        public var renamed: Bool { source != destination }

        public init(source: String, destination: String) {
            self.source = source
            self.destination = destination
        }
    }

    public let configData: Data
    public let preferences: Preferences
    public let notes: [NoteCopy]
    public let report: [String]

    public var renamedCount: Int { notes.filter(\.renamed).count }

    public init(configData: Data, preferences: Preferences, notes: [NoteCopy], report: [String]) {
        self.configData = configData
        self.preferences = preferences
        self.notes = notes
        self.report = report
    }
}

public enum BackupError: Error, LocalizedError, Equatable {
    case unreadableConfig

    public var errorDescription: String? {
        switch self {
        case .unreadableConfig: return "No readable config.json in that folder."
        }
    }
}

/// Export and import of config and notes. Clipboard history is excluded by design: it is encrypted
/// under this Mac's Keychain key and cannot be restored elsewhere.
public enum BackupFolder {
    /// Dated folder an export creates inside the folder the user picked.
    public static func exportName(on date: Date = Date()) -> String {
        "Volant-Backup-" + date.formatted(.iso8601.year().month().day())
    }

    /// Reads a backup folder and resolves what importing it would change. Nothing is written.
    public static func plan(source: URL,
                            notesDestination: URL,
                            fileManager: FileManager = .default) throws -> BackupPlan {
        let configURL = source.appendingPathComponent("config.json")
        guard let data = try? Data(contentsOf: configURL),
              let preferences = try? JSONDecoder().decode(Preferences.self, from: data) else {
            throw BackupError.unreadableConfig
        }
        let notesURL = source.appendingPathComponent("Notes")
        let incoming = ((try? fileManager.contentsOfDirectory(atPath: notesURL.path)) ?? [])
            .filter { $0.hasSuffix(".md") }
            .sorted()
        var taken = Set(((try? fileManager.contentsOfDirectory(atPath: notesDestination.path)) ?? []))
        var copies: [BackupPlan.NoteCopy] = []
        var report: [String] = []
        for name in incoming {
            let destination = freeName(for: name, taken: taken)
            taken.insert(destination)
            copies.append(BackupPlan.NoteCopy(source: name, destination: destination))
        }
        let renamed = copies.filter(\.renamed).count
        if renamed > 0 {
            report.append("\(renamed) note\(renamed == 1 ? "" : "s") already exist by name and will be added alongside the originals.")
        }
        return BackupPlan(configData: data, preferences: preferences, notes: copies, report: report)
    }

    /// Writes the planned config and notes. Existing notes are never replaced.
    public static func apply(_ plan: BackupPlan,
                             source: URL,
                             configURL: URL,
                             notesDestination: URL,
                             fileManager: FileManager = .default) throws {
        try plan.configData.write(to: configURL, options: .atomic)
        guard !plan.notes.isEmpty else { return }
        let notesURL = source.appendingPathComponent("Notes")
        try fileManager.createDirectory(at: notesDestination, withIntermediateDirectories: true)
        for note in plan.notes {
            try fileManager.copyItem(at: notesURL.appendingPathComponent(note.source),
                                     to: notesDestination.appendingPathComponent(note.destination))
        }
    }

    /// `note.md` becomes `imported-note.md`, then `imported-2-note.md`, and so on until it is free.
    static func freeName(for name: String, taken: Set<String>) -> String {
        guard taken.contains(name) else { return name }
        let candidate = "imported-" + name
        guard taken.contains(candidate) else { return candidate }
        var counter = 2
        while taken.contains("imported-\(counter)-" + name) { counter += 1 }
        return "imported-\(counter)-" + name
    }
}
