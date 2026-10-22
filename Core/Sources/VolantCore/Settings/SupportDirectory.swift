import Foundation

/// Where Volant keeps its data inside Application Support, and the one-time move from the folder
/// releases up to 0.3.14 used, `Vey`, which was the app's name before Volant.
public struct SupportDirectory: Equatable {
    public static let name = "Volant"
    public static let legacyName = "Vey"

    public enum Outcome: Equatable {
        case current
        case moved(from: URL)
        case kept(legacy: URL)
    }

    public let url: URL
    public let outcome: Outcome

    /// Moves `Vey` to `Volant` when only `Vey` exists. The move is a rename within one folder,
    /// so it either happens whole or not at all. If it fails, this launch keeps using `Vey`
    /// and the next launch tries again; an existing `Volant` folder is never merged or replaced.
    public static func resolve(in base: URL, fileManager: FileManager = .default) -> SupportDirectory {
        let current = base.appendingPathComponent(name, isDirectory: true)
        let legacy = base.appendingPathComponent(legacyName, isDirectory: true)
        var isDirectory: ObjCBool = false
        guard !fileManager.fileExists(atPath: current.path),
              fileManager.fileExists(atPath: legacy.path, isDirectory: &isDirectory), isDirectory.boolValue
        else { return SupportDirectory(url: current, outcome: .current) }
        do {
            try fileManager.moveItem(at: legacy, to: current)
            return SupportDirectory(url: current, outcome: .moved(from: legacy))
        } catch {
            return SupportDirectory(url: legacy, outcome: .kept(legacy: legacy))
        }
    }

    /// Carries preferences that depend on the old names over to the new ones: the Notes window's
    /// saved frame, and after a move, Notes settings keyed by a path inside the old folder.
    /// Values already saved under a new key are left alone.
    public func moveLegacyDefaults(in defaults: UserDefaults) {
        var renames = ["NSWindow Frame VeyNotes": "NSWindow Frame VolantNotes"]
        if case .moved(let legacy) = outcome {
            let prefix = "notes." + legacy.path + "/"
            for key in defaults.dictionaryRepresentation().keys where key.hasPrefix(prefix) {
                renames[key] = "notes." + url.path + "/" + key.dropFirst(prefix.count)
            }
        }
        for (old, new) in renames {
            guard let value = defaults.object(forKey: old) else { continue }
            if defaults.object(forKey: new) == nil { defaults.set(value, forKey: new) }
            defaults.removeObject(forKey: old)
        }
    }
}
