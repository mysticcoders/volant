import AppKit
import Carbon

/// Stands in for "another app" that already owns a global shortcut: registers the given key code
/// and Carbon modifier mask with RegisterEventHotKey, prints the status, and keeps it registered
/// until killed. Every press it receives is logged so the test can tell who got the key.
let arguments = CommandLine.arguments
guard arguments.count >= 3, let code = UInt32(arguments[1]), let modifiers = UInt32(arguments[2]) else {
    print("usage: hold-hotkey <key code> <carbon modifiers> [exclusive]")
    exit(2)
}
var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
InstallEventHandler(GetApplicationEventTarget(), { _, _, _ in
    print("hold-hotkey: pressed"); fflush(stdout); return noErr
}, 1, &spec, nil, nil)
var ref: EventHotKeyRef?
let options: OptionBits = arguments.count > 3 ? OptionBits(kEventHotKeyExclusive) : 0
let status = RegisterEventHotKey(code, modifiers, EventHotKeyID(signature: 0x484F4C44, id: 1), GetApplicationEventTarget(), options, &ref)
print("hold-hotkey: registered status \(status)")
fflush(stdout)
NSApplication.shared.setActivationPolicy(.prohibited)
NSApplication.shared.run()
