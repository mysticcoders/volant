import AppKit
import SwiftUI
import Carbon.HIToolbox

struct ShortcutRecorder: NSViewRepresentable {
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

final class RecorderButton: NSButton {
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
