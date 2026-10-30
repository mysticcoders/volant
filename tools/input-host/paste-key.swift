// Checks PasteKey against keyboard layouts installed with macOS: whichever key types "v" with Command
// held must be chosen, without switching the owner's input source.
import Carbon.HIToolbox
import Foundation

func require(_ condition: @autoclosure () -> Bool, _ message: String) { precondition(condition(), message) }

/// An installed keyboard layout by its input source ID, enabled or not.
func layout(_ id: String) -> TISInputSource? {
    let filter = [kTISPropertyInputSourceID as String: id] as CFDictionary
    let list = TISCreateInputSourceList(filter, true)?.takeRetainedValue() as? [TISInputSource]
    return list?.first
}

let cases: [(id: String, expected: Int, name: String)] = [
    ("com.apple.keylayout.US", kVK_ANSI_V, "U.S. pastes with the physical V key"),
    ("com.apple.keylayout.Dvorak", kVK_ANSI_Period, "Dvorak pastes with the key that types v there"),
    ("com.apple.keylayout.DVORAK-QWERTYCMD", kVK_ANSI_V, "Dvorak – QWERTY ⌘ switches to QWERTY under Command, so the physical V key"),
    ("com.apple.keylayout.French", kVK_ANSI_V, "AZERTY keeps V where QWERTY has it"),
]
for test in cases {
    guard let source = layout(test.id) else { print("SKIP: \(test.id) is not installed"); continue }
    let found = PasteKey.keyCode(in: source)
    require(found == CGKeyCode(test.expected), "\(test.name): expected \(test.expected), found \(String(describing: found))")
    print("Passed: \(test.name).")
}
require(PasteKey.keyCode(typing: "v", layout: Data()) == nil, "unreadable layout data finds no key")
print("Passed: unreadable layout data finds no key, so the physical V key is used; the current layout resolves to \(PasteKey.current()).")
