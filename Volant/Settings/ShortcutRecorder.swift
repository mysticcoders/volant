import AppKit
import SwiftUI
import Carbon.HIToolbox

struct ShortcutRecorder: NSViewRepresentable {
    @Binding var value: String
    var removable = false
    var onMissedKey: (Bool) -> Void = { _ in }
    /// The button keeps the width its row gives it and truncates a long title, so "Press shortcut…"
    /// cannot widen a 160-point column past the window's edge.
    func makeNSView(context: Context) -> RecorderButton {
        let button = RecorderButton()
        button.bezelStyle = .rounded
        button.lineBreakMode = .byTruncatingTail
        button.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        button.target = button
        button.action = #selector(RecorderButton.beginRecording)
        return button
    }
    func updateNSView(_ button: RecorderButton, context: Context) {
        button.isEnabled = context.environment.isEnabled
        button.removable = removable
        button.value = value
        button.onRecord = { value = $0 }
        button.onMissedKey = onMissedKey
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
    /// Reports true when Command, Control or Option was held and released while recording without any
    /// key arriving, which is what happens when macOS or another app's global shortcut takes the key
    /// first (its key down and key up never reach Volant), and false when that no longer applies.
    var onMissedKey: (Bool) -> Void = { _ in }
    private var heldGlobalModifier = false
    private var sawKey = false
    private var reportedMiss = false
    private func reportMiss(_ missed: Bool) {
        guard missed != reportedMiss else { return }
        reportedMiss = missed
        onMissedKey(missed)
    }
    /// Volant's own hotkeys are suspended for exactly as long as the button records, so pressing a
    /// combination Volant already uses reaches this button instead of firing that shortcut.
    private var recording = false {
        didSet {
            guard recording != suspendsHotKeys else { return }
            suspendsHotKeys = recording
            if recording { HotKeyCenter.shared.suspend() } else { HotKeyCenter.shared.resume() }
            heldGlobalModifier = false
            sawKey = false
            reportMiss(false)
        }
    }
    private var suspendsHotKeys = false
    deinit { if suspendsHotKeys { HotKeyCenter.shared.resume() } }
    /// Recording ends when the button leaves its window or the window stops being key, so switching
    /// away or closing Settings mid-recording never leaves Volant's hotkeys suspended.
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        NotificationCenter.default.removeObserver(self, name: NSWindow.didResignKeyNotification, object: nil)
        if let window {
            NotificationCenter.default.addObserver(self, selector: #selector(stopRecording), name: NSWindow.didResignKeyNotification, object: window)
        } else {
            stopRecording()
        }
    }
    @objc private func stopRecording() {
        guard recording else { return }
        recording = false
        updateTitle()
    }
    override var acceptsFirstResponder: Bool { true }
    @objc func beginRecording() { recording = true; window?.makeFirstResponder(self); updateTitle() }
    func updateTitle() {
        title = recording ? "Press shortcut…" : value.isEmpty ? "Record Hotkey" : KeyCombo.display(value)
        toolTip = recording ? "Press a shortcut, or Esc to cancel." : nil
        setAccessibilityLabel("Global shortcut: " + (value.isEmpty || recording ? title : value))
        setAccessibilityHelp(recording ? "Press a shortcut, or Escape to cancel." : nil)
        updateRemoveButton()
    }
    override func resignFirstResponder() -> Bool { recording = false; updateTitle(); return super.resignFirstResponder() }
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard recording else { return super.performKeyEquivalent(with: event) }
        keyDown(with: event)
        return true
    }
    override func flagsChanged(with event: NSEvent) {
        guard recording else { return super.flagsChanged(with: event) }
        let flags = event.modifierFlags.intersection([.command, .control, .option, .shift])
        if !flags.isDisjoint(with: [.command, .control, .option]) { heldGlobalModifier = true }
        guard flags.isEmpty else { return }
        if heldGlobalModifier && !sawKey { reportMiss(true) }
        heldGlobalModifier = false
        sawKey = false
    }
    override func keyDown(with event: NSEvent) {
        if recording { sawKey = true; reportMiss(false) }
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
