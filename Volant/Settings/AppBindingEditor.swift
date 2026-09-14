import AppKit
import SwiftUI
import Carbon.HIToolbox

struct AppBindingEditor: View {
    let app: AppEntry
    let configURL: URL
    let onChange: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var alias = ""
    @State private var originalAlias = ""
    @State private var hotKey = ""
    @State private var originalHotKey = ""
    @State private var expected: Data?
    @State private var error: String?
    private var bundleID: String? { Bundle(url: app.url)?.bundleIdentifier }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(app.name).font(.title2.bold())
            Text("Global shortcut").font(.headline)
            HStack {
                ShortcutRecorder(value: $hotKey).frame(height: 32)
                Button("Clear") { hotKey = "" }.disabled(hotKey.isEmpty)
            }
            Text("Press to launch or focus this app. Press again when it is frontmost to hide it. Use Command, Control or Option with a key.")
                .font(.callout).foregroundStyle(.secondary)
            Divider()
            Text("Launcher alias").font(.headline)
            TextField("For example: c", text: $alias).textFieldStyle(.roundedBorder)
            Text("Type this alias in Volant, then press Return. Clearing it removes this alias; other aliases are preserved.")
                .font(.callout).foregroundStyle(.secondary)
            if let error { Text(error).foregroundStyle(.red).font(.callout).fixedSize(horizontal: false, vertical: true) }
            HStack {
                Button("Reload") { load() }
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Save") { save() }.keyboardShortcut(.defaultAction).disabled(expected == nil || bundleID == nil)
            }
        }.padding(24).frame(width: 450).background(Color(nsColor: .windowBackgroundColor))
            .onAppear { load() }
    }
    private func load() {
        do {
            let bytes = try Data(contentsOf: configURL)
            let config = try JSONDecoder().decode(Preferences.self, from: bytes)
            expected = bytes
            originalAlias = config.aliases.filter { $0.value == app.url.path || $0.value == app.name }.keys.sorted().first ?? ""
            alias = originalAlias
            originalHotKey = config.appHotKeys.first { $0.bundleIdentifier == bundleID }?.hotKey ?? ""
            hotKey = originalHotKey
            error = bundleID == nil ? "This application has no bundle identifier and cannot receive a global shortcut." : nil
        } catch { self.error = error.localizedDescription; expected = nil }
    }
    private func save() {
        guard let expected, let bundleID else { return }
        do {
            try AppBindingStore.save(bundleID: bundleID, path: app.url.path, originalAlias: originalAlias, alias: alias,
                                     hotKey: hotKey, expected: expected, at: configURL) { combo in
                // An unchanged binding is already registered by Volant. New combinations must be available.
                combo == KeyCombo(parsing: originalHotKey) || HotKeyCenter.shared.isAvailable(combo)
            }
            onChange()
            dismiss()
        } catch { self.error = error.localizedDescription }
    }
}

private struct ShortcutRecorder: NSViewRepresentable {
    @Binding var value: String
    func makeNSView(context: Context) -> RecorderButton {
        let button = RecorderButton()
        button.bezelStyle = .rounded
        button.target = button
        button.action = #selector(RecorderButton.beginRecording)
        return button
    }
    func updateNSView(_ button: RecorderButton, context: Context) {
        button.value = value
        button.onRecord = { value = $0 }
        button.updateTitle()
    }
}

private final class RecorderButton: NSButton {
    var value = ""
    var onRecord: (String) -> Void = { _ in }
    private var recording = false
    override var acceptsFirstResponder: Bool { true }
    @objc func beginRecording() { recording = true; window?.makeFirstResponder(self); updateTitle() }
    func updateTitle() {
        title = recording ? "Press shortcut… (Esc to cancel)" : value.isEmpty ? "Record Shortcut…" : value
        setAccessibilityLabel("Global shortcut: " + title)
    }
    override func resignFirstResponder() -> Bool { recording = false; updateTitle(); return super.resignFirstResponder() }
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard recording else { return super.performKeyEquivalent(with: event) }
        keyDown(with: event)
        return true
    }
    override func keyDown(with event: NSEvent) {
        guard recording else { super.keyDown(with: event); return }
        if event.keyCode == UInt16(kVK_Escape) { recording = false; updateTitle(); return }
        guard let key = KeyCombo.keyCodes.keys.sorted().first(where: { KeyCombo.keyCodes[$0] == UInt32(event.keyCode) }) else { NSSound.beep(); return }
        var parts: [String] = []
        if event.modifierFlags.contains(.command) { parts.append("cmd") }
        if event.modifierFlags.contains(.control) { parts.append("ctrl") }
        if event.modifierFlags.contains(.option) { parts.append("option") }
        if event.modifierFlags.contains(.shift) { parts.append("shift") }
        guard event.modifierFlags.intersection([.command, .control, .option]).isEmpty == false else { NSSound.beep(); return }
        parts.append(key)
        recording = false
        value = parts.joined(separator: "+")
        onRecord(value)
        updateTitle()
    }
}
