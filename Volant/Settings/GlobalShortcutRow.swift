import SwiftUI
import Carbon.HIToolbox

/// Patches one global binding without discarding edits elsewhere in configuration.
enum GlobalShortcutStore {
    static func save(key: String, value: String, expectedValue: String, at url: URL,
                     available: (KeyCombo) -> Bool) throws {
        guard ["summonHotKey", "notesHotKey"].contains(key) else { throw BindingFailure(message: "Unknown global shortcut.") }
        let data = try Data(contentsOf: url)
        let config = try JSONDecoder().decode(Preferences.self, from: data)
        let current = key == "summonHotKey" ? config.summonHotKey : config.notesHotKey
        guard current == expectedValue else { throw BindingFailure(message: "This shortcut changed in the configuration file. Reload Configuration before saving again.") }
        guard let combo = KeyCombo(parsing: value), combo.carbonModifiers & UInt32(cmdKey | controlKey | optionKey) != 0 else {
            throw BindingFailure(message: "Include Command, Control or Option with a key.")
        }
        let other = key == "summonHotKey" ? config.notesHotKey : config.summonHotKey
        guard !([other] + config.appHotKeys.map(\.hotKey)).contains(where: { KeyCombo(parsing: $0) == combo }) else {
            throw BindingFailure(message: "That shortcut is already assigned in Volant.")
        }
        guard combo == KeyCombo(parsing: current) || available(combo) else {
            throw BindingFailure(message: "macOS or another app is using that shortcut. Choose another combination.")
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
    @State private var draft: String
    @State private var error: String?

    init(title: String, key: String, value: String, configURL: URL, onChange: @escaping () -> Void) {
        self.title = title
        self.key = key
        self.value = value
        self.configURL = configURL
        self.onChange = onChange
        _draft = State(initialValue: value)
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title).frame(width: 95, alignment: .leading)
                ShortcutRecorder(value: $draft).frame(height: 32).accessibilityLabel(title + " shortcut: " + draft)
                Button("Save", action: save).disabled(draft == value).accessibilityLabel("Save " + title + " shortcut")
            }
            if let error { Text(error).font(.callout).foregroundStyle(.red).fixedSize(horizontal: false, vertical: true) }
        }
        .onChange(of: value) { old, new in
            if draft == old { draft = new }
        }
    }
    private func save() {
        do {
            try GlobalShortcutStore.save(key: key, value: draft, expectedValue: value, at: configURL,
                                         available: { HotKeyCenter.shared.isAvailable($0) })
            error = nil
            onChange()
        } catch { self.error = error.localizedDescription }
    }
}
