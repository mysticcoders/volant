import Foundation
import VolantCore

/// Grants are bound to the complete manifest, including code hash and capabilities.
/// A changed extension is disabled again; edits preserve unrelated config fields.
enum ExtensionApproval {
    static func communityAllowed(at url: URL) -> Bool {
        (try? read(url)["communityExtensionsAllowed"] as? Bool) == true
    }
    static func updateCommunityAllowed(_ allowed: Bool, expected: Bool, at url: URL) throws {
        var object = try read(url)
        guard (object["communityExtensionsAllowed"] as? Bool == true) == expected else { throw CocoaError(.fileWriteFileExists) }
        object["communityExtensionsAllowed"] = allowed
        try JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys]).write(to: url, options: .atomic)
    }
    static func fingerprint(_ manifest: ExtensionManifest) throws -> String {
        let encoder = JSONEncoder(); encoder.outputFormatting = .sortedKeys
        return Integrity.sha256(try encoder.encode(manifest))
    }
    static func enabled(_ manifest: ExtensionManifest, at url: URL) -> Bool {
        guard let object = try? read(url), let grants = object["extensions"] as? [String: Any],
              let grant = grants[manifest.id] as? [String: Any] else { return false }
        return grant["enabled"] as? Bool == true && grant["fingerprint"] as? String == (try? fingerprint(manifest))
    }
    static func update(_ manifest: ExtensionManifest, enabled: Bool, expected: Bool, at url: URL) throws {
        var object = try read(url)
        guard self.enabled(manifest, at: url) == expected else { throw CocoaError(.fileWriteFileExists) }
        var grants = object["extensions"] as? [String: Any] ?? [:]
        var grant = grants[manifest.id] as? [String: Any] ?? [:]
        grant["enabled"] = enabled
        grant["fingerprint"] = try fingerprint(manifest)
        grants[manifest.id] = grant; object["extensions"] = grants
        try JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys]).write(to: url, options: .atomic)
    }
    private static func read(_ url: URL) throws -> [String: Any] {
        guard let object = try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any],
              object["extensions"] == nil || object["extensions"] is [String: Any] else { throw CocoaError(.fileReadCorruptFile) }
        return object
    }
}
