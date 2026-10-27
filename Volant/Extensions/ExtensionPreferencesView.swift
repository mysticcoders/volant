import SwiftUI
import VolantCore

/// The sheet behind an extension's Preferences… button: one native control per declared preference,
/// edited locally and saved together. Saving refuses when the stored values changed since the sheet
/// opened, so a second Settings window or a config.json edit is never silently overwritten.
struct ExtensionPreferencesView: View {
    let ext: InstalledExtension
    let manager: ExtensionManager
    let done: () -> Void
    @State private var values: [String: JSONValue] = [:]
    @State private var opened: [String: JSONValue] = [:]
    @State private var error: String?

    private var declared: [ExtensionPreference] { ext.manifest.declaredPreferences }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("\(ext.name) Preferences", comment: "Title of an extension's preferences sheet; the value is the extension's name").font(.title2.bold())
            Form {
                ForEach(declared, id: \.id) { preference in
                    control(preference)
                }
            }
            .formStyle(.settings)
            .frame(height: min(CGFloat(declared.count) * 58 + 8, 420))
            if let error {
                Text(error).foregroundStyle(.red).font(.callout).accessibilityIdentifier("extension-preferences-error")
            }
            HStack {
                Button(String(localized: "Restore Defaults", comment: "Resets an extension's preferences to their defaults")) {
                    values = ExtensionPreferences.resolve(declared, stored: [:])
                }
                Spacer()
                Button(String(localized: "Cancel", comment: "Closes a sheet without saving")) { done() }.keyboardShortcut(.cancelAction)
                Button(String(localized: "Save", comment: "Saves an extension's preferences")) { save() }.keyboardShortcut(.defaultAction)
            }
        }
        .padding(24).frame(width: 460).background(Color(nsColor: .windowBackgroundColor))
        .onAppear {
            opened = ExtensionPreferenceStore.values(for: ext.id, at: manager.configURL)
            values = manager.preferenceValues(ext)
        }
    }

    @ViewBuilder private func control(_ preference: ExtensionPreference) -> some View {
        let description = preference.description.map { Text(verbatim: $0) }
        switch preference.type {
        case .toggle:
            Toggle(isOn: Binding(get: { values[preference.id] == .bool(true) }, set: { values[preference.id] = .bool($0) })) {
                Text(verbatim: preference.title)
                if let description { description }
            }
        case .text:
            LabeledContent {
                TextField(text: Binding(get: { if case .string(let text)? = values[preference.id] { return text }; return "" },
                                        set: { values[preference.id] = .string(String($0.filter { !$0.isNewline }.prefix(preference.maxLength ?? ExtensionPreference.defaultTextLength))) }),
                          prompt: preference.placeholder.map { Text(verbatim: $0) }) { Text(verbatim: preference.title) }
                    .labelsHidden().frame(width: 180)
            } label: {
                Text(verbatim: preference.title)
                if let description { description }
            }
        case .dropdown:
            LabeledContent {
                Picker(selection: Binding(get: { if case .string(let choice)? = values[preference.id] { return choice }; return "" },
                                          set: { values[preference.id] = .string($0) })) {
                    ForEach(preference.choices ?? [], id: \.id) { choice in Text(verbatim: choice.title).tag(choice.id) }
                } label: { Text(verbatim: preference.title) }
                    .labelsHidden().fixedSize()
            } label: {
                Text(verbatim: preference.title)
                if let description { description }
            }
        case .number:
            LabeledContent {
                TextField(value: Binding(get: { if case .number(let number)? = values[preference.id] { return number }; return preference.min ?? 0 },
                                         set: { values[preference.id] = .number(Swift.min(Swift.max($0, preference.min ?? $0), preference.max ?? $0)) }),
                          format: .number) { Text(verbatim: preference.title) }
                    .labelsHidden().multilineTextAlignment(.trailing).frame(width: 90)
            } label: {
                Text(verbatim: preference.title)
                if let description { description }
            }
        }
    }

    private func save() {
        do {
            try manager.savePreferences(values, for: ext, expected: opened)
            done()
        } catch {
            self.error = String(localized: "These preferences changed elsewhere. Close this sheet and open it again to see the current values.",
                                comment: "Extension preferences save error")
        }
    }
}
