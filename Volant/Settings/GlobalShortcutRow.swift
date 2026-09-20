import SwiftUI
import Carbon.HIToolbox
import VolantCore

/// Patches one global binding without discarding edits elsewhere in configuration.
enum GlobalShortcutStore {
    static func save(key: String, value: String, expectedValue: String, at url: URL,
                     available: (KeyCombo) -> Bool) throws {
        guard ["summonHotKey", "notesHotKey", "emojiHotKey"].contains(key) else { throw BindingFailure(message: "Unknown global shortcut.") }
        let data = try Data(contentsOf: url)
        let config = try JSONDecoder().decode(Preferences.self, from: data)
        let bindings = ["summonHotKey": config.summonHotKey, "notesHotKey": config.notesHotKey, "emojiHotKey": config.emojiHotKey]
        let current = bindings[key] ?? ""
        guard current == expectedValue else { throw BindingFailure(message: "This shortcut changed in the configuration file. Reload Configuration before saving again.") }
        if !value.isEmpty {
        guard let combo = KeyCombo(parsing: value), combo.carbonModifiers & UInt32(cmdKey | controlKey | optionKey) != 0 else {
            throw BindingFailure(message: "Include Command, Control or Option with a key.")
        }
        let others = bindings.filter { $0.key != key }.map(\.value)
        guard !(others + config.appHotKeys.map(\.hotKey)).contains(where: { KeyCombo(parsing: $0) == combo }) else {
            throw BindingFailure(message: "That shortcut is already assigned in Volant.")
        }
        guard combo == KeyCombo(parsing: current) || available(combo) else {
            throw BindingFailure(message: "macOS or another app is using that shortcut. Choose another combination.")
        }
        }
        guard var object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw CocoaError(.fileReadCorruptFile) }
        object[key] = value
        let updated = try JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys])
        _ = try JSONDecoder().decode(Preferences.self, from: updated)
        try updated.write(to: url, options: .atomic)
    }
}

struct GlobalShortcutRow: View {
    let title: String
    let key: String
    let value: String
    let configURL: URL
    let onChange: () -> Void
    var body: some View {
        HStack(alignment: .top) {
            Text(title).frame(width: 95, alignment: .leading).padding(.top, 8)
            ShortcutControl(title: title, value: value) { replacement in
                try GlobalShortcutStore.save(key: key, value: replacement, expectedValue: value, at: configURL,
                                             available: { HotKeyCenter.shared.isAvailable($0) })
                onChange()
            }
        }
    }
}
