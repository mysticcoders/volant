import Foundation
import Carbon.HIToolbox

struct BindingFailure: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

/// Patch only this app's binding, preserving unknown fields and unrelated aliases.
enum AppBindingStore {


    static func save(bundleID: String, path: String, originalAlias: String, alias: String, hotKey: String,
                     expected: Data, at url: URL, available: (KeyCombo) -> Bool) throws {
        let current = try Data(contentsOf: url)
        guard current == expected else { throw BindingFailure(message: "Configuration changed. Reload this editor before saving again.") }
        let config = try JSONDecoder().decode(Preferences.self, from: current)
        guard var object = try JSONSerialization.jsonObject(with: current) as? [String: Any] else { throw CocoaError(.fileReadCorruptFile) }
        let alias = alias.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if !alias.isEmpty {
            guard !LauncherRouting.isReserved(alias), !alias.contains(where: { $0.isWhitespace }),
                  !alias.hasPrefix("/"), !alias.hasPrefix("@"), !alias.hasPrefix(":"),
                  alias.rangeOfCharacter(from: .letters) != nil else {
                throw BindingFailure(message: "Choose a single word or letter that is not a built-in command.")
            }
            guard !config.aliases.keys.contains(where: { $0.lowercased() == alias && $0 != originalAlias }),
                  !config.quicklinks.contains(where: { $0.name.lowercased() == alias }),
                  !config.snippets.contains(where: { $0.keyword.lowercased() == alias }) else {
                throw BindingFailure(message: "That alias is already used by another alias, quicklink or snippet.")
            }
        }
        if !hotKey.isEmpty {
            guard let combo = KeyCombo(parsing: hotKey), combo.carbonModifiers & UInt32(cmdKey | controlKey | optionKey) != 0 else {
                throw BindingFailure(message: "Include Command, Control or Option in a global shortcut.")
            }
            let others = [config.summonHotKey, config.notesHotKey] + config.appHotKeys.filter { $0.bundleIdentifier != bundleID }.map(\.hotKey)
            guard !others.contains(where: { KeyCombo(parsing: $0) == combo }) else { throw BindingFailure(message: "That shortcut is already assigned in Volant.") }
            guard available(combo) else { throw BindingFailure(message: "macOS or another app is using that shortcut. Choose another combination.") }
        }
        var aliases = object["aliases"] as? [String: String] ?? [:]
        if !originalAlias.isEmpty { aliases.removeValue(forKey: originalAlias) }
        if !alias.isEmpty { aliases[alias] = path }
        object["aliases"] = aliases
        var entries = object["appHotKeys"] as? [[String: Any]] ?? []
        var entry = entries.first { $0["bundleIdentifier"] as? String == bundleID } ?? [:]
        entries.removeAll { $0["bundleIdentifier"] as? String == bundleID }
        if !hotKey.isEmpty {
            entry["bundleIdentifier"] = bundleID
            entry["hotKey"] = hotKey
            entries.append(entry)
        }
        object["appHotKeys"] = entries
        let data = try JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys])
        _ = try JSONDecoder().decode(Preferences.self, from: data)
        try data.write(to: url, options: .atomic)
    }
}
