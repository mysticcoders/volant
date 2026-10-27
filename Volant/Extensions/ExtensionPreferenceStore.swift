import Foundation
import VolantCore

/// The owner's choices for extensions' declared preferences, in config.json under `extensionPreferences`,
/// keyed by extension id then preference id. Edits read the latest file, change one extension's values,
/// keep every other field, and refuse when the values changed since the owner opened them. Kept when an
/// extension is disabled or updated, removed when it is uninstalled, and never synced.
enum ExtensionPreferenceStore {
    static let key = "extensionPreferences"

    /// The stored values for one extension, whatever their shape; `ExtensionPreferences.resolve` decides
    /// which still fit.
    static func values(for id: String, at url: URL) -> [String: JSONValue] {
        guard let object = try? read(url), let all = object[key] as? [String: Any], let values = all[id] as? [String: Any],
              let data = try? JSONSerialization.data(withJSONObject: values),
              case .object(let decoded)? = try? JSONDecoder().decode(JSONValue.self, from: data) else { return [:] }
        return decoded
    }

    /// Replaces one extension's stored values with `values`, or removes them when empty. Throws when the
    /// stored values are no longer `expected`, so two editors never overwrite each other.
    static func save(_ values: [String: JSONValue], for id: String, expected: [String: JSONValue], at url: URL) throws {
        var object = try read(url)
        guard Self.values(for: id, at: url) == expected else { throw CocoaError(.fileWriteFileExists) }
        var all = object[key] as? [String: Any] ?? [:]
        if values.isEmpty {
            all[id] = nil
        } else {
            all[id] = try JSONSerialization.jsonObject(with: JSONEncoder().encode(JSONValue.object(values)))
        }
        object[key] = all.isEmpty ? nil : all
        try JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys]).write(to: url, options: .atomic)
    }

    /// Drops an extension's values entirely, for uninstalling it.
    static func forget(_ id: String, at url: URL) throws {
        try save([:], for: id, expected: values(for: id, at: url), at: url)
    }

    private static func read(_ url: URL) throws -> [String: Any] {
        guard let object = try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any],
              object[key] == nil || object[key] is [String: Any] else { throw CocoaError(.fileReadCorruptFile) }
        return object
    }
}
