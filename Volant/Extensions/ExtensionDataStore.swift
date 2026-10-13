import Foundation
import VolantCore

/// The JSON object each storage-using extension keeps on this Mac, one file per extension in
/// `Application Support/Vey/ExtensionData`. File names are a hash of the extension ID, so no ID can
/// choose a path. Writes are atomic. The data is per Mac: it is not synced through iCloud and not part
/// of Volant's backups or exports. Stored values are never logged.
struct ExtensionDataStore {
    let directory: URL

    static var defaultDirectory: URL { Preferences.supportDirectory.appendingPathComponent("ExtensionData", isDirectory: true) }

    private func url(_ id: String) -> URL {
        directory.appendingPathComponent(Integrity.sha256(Data(id.utf8)) + ".json")
    }

    /// The saved object, or `{}` when there is none or it can no longer be read.
    func load(_ id: String) -> JSONValue {
        let file = url(id)
        guard let size = (try? FileManager.default.attributesOfItem(atPath: file.path))?[.size] as? Int,
              size <= ExtensionStorage.maximumBytes else { return ExtensionStorage.empty }
        return ExtensionStorage.decode(try? Data(contentsOf: file))
    }

    /// Replaces the saved object after checking its shape and size; on any error the old one stays.
    func save(_ value: JSONValue, for id: String) throws {
        let data = try ExtensionStorage.encode(value)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try data.write(to: url(id), options: .atomic)
    }

    func hasData(_ id: String) -> Bool { FileManager.default.fileExists(atPath: url(id).path) }

    func clear(_ id: String) throws {
        let file = url(id)
        guard FileManager.default.fileExists(atPath: file.path) else { return }
        try FileManager.default.removeItem(at: file)
    }
}
