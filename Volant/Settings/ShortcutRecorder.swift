import AppKit
import SwiftUI
import Carbon.HIToolbox

struct ShortcutRecorder: NSViewRepresentable {
    @Binding var value: String
    var removable = false
    func makeNSView(context: Context) -> RecorderButton {
        let button = RecorderButton()
        button.bezelStyle = .rounded
        button.target = button
        button.action = #selector(RecorderButton.beginRecording)
        return button
    }
    func updateNSView(_ button: RecorderButton, context: Context) {
        button.isEnabled = context.environment.isEnabled
        button.removable = removable
        button.value = value
        button.onRecord = { value = $0 }
        button.updateTitle()
    }
}

final class RecorderButton: NSButton {
    var removable = false
    var value = ""
    private var hoverTracking: NSTrackingArea?
    private var hovering = false
    private lazy var removeButton: NSButton = {
        let button = NSButton(image: NSImage(systemSymbolName: "xmark", accessibilityDescription: "Remove shortcut")!, target: self, action: #selector(removeShortcut))
        button.isBordered = false
        button.toolTip = "Remove shortcut"
        button.isHidden = true
        addSubview(button)
        return button
    }()
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let hoverTracking { removeTrackingArea(hoverTracking) }
        let tracking = NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self)
        addTrackingArea(tracking)
        hoverTracking = tracking
    }
    override func mouseEntered(with event: NSEvent) { hovering = true; updateRemoveButton() }
    override func mouseExited(with event: NSEvent) { hovering = false; updateRemoveButton() }
    override func layout() {
        super.layout()
        removeButton.frame = NSRect(x: bounds.maxX - 25, y: bounds.midY - 9, width: 18, height: 18)
    }
    private func updateRemoveButton() {
        removeButton.frame = NSRect(x: bounds.maxX - 25, y: bounds.midY - 9, width: 18, height: 18)
        removeButton.isHidden = !removable || value.isEmpty || !hovering || recording
    }
    @objc private func removeShortcut() {
        guard removable && isEnabled else { return }
        recording = false
        value = ""
        onRecord("")
        updateTitle()
    }
    var onRecord: (String) -> Void = { _ in }
    private var recording = false
    override var acceptsFirstResponder: Bool { true }
    @objc func beginRecording() { recording = true; window?.makeFirstResponder(self); updateTitle() }
    func updateTitle() {
        title = recording ? "Press shortcut… (Esc to cancel)" : value.isEmpty ? "Record Hotkey" : KeyCombo.display(value)
        setAccessibilityLabel("Global shortcut: " + (value.isEmpty || recording ? title : value))
        updateRemoveButton()
    }
    override func resignFirstResponder() -> Bool { recording = false; updateTitle(); return super.resignFirstResponder() }
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard recording else { return super.performKeyEquivalent(with: event) }
        keyDown(with: event)
        return true
    }
    override func keyDown(with event: NSEvent) {
        guard recording else {
            if removable && event.keyCode == UInt16(kVK_Delete) { removeShortcut() }
            else { super.keyDown(with: event) }
            return
        }
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
