import Carbon.HIToolbox
import CoreGraphics
import Foundation

/// The key that types "v" while Command is held in a keyboard layout, so the input helper's
/// Command-V pastes on any layout. macOS matches shortcuts by the character a key types, so on plain
/// Dvorak the physical V key sends Command-K. "Dvorak – QWERTY ⌘" style layouts switch to QWERTY under
/// Command, and for them this resolves to the physical V key as before.
enum PasteKey {
    static let fallback = CGKeyCode(kVK_ANSI_V)
    /// Virtual key codes 0 through 127 cover every character key on Apple keyboards.
    private static let keyCodes = 0..<128

    /// The paste key for the keyboard layout in use now, or the physical V key when the layout
    /// can't be read.
    static func current() -> CGKeyCode {
        guard let source = TISCopyCurrentKeyboardLayoutInputSource()?.takeRetainedValue() else { return fallback }
        return keyCode(in: source) ?? fallback
    }

    /// The key that types "v" with Command held in an input source's layout, or nil when the source
    /// has no Unicode layout data or no key types "v".
    static func keyCode(in source: TISInputSource) -> CGKeyCode? {
        guard let pointer = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData) else { return nil }
        return keyCode(typing: "v", layout: Unmanaged<CFData>.fromOpaque(pointer).takeUnretainedValue() as Data)
    }

    /// Searches a `UCKeyboardLayout` for the key that produces `character` with the Command modifier,
    /// preferring the lowest key code when several do.
    static func keyCode(typing character: Character, layout: Data) -> CGKeyCode? {
        let keyboardType = UInt32(LMGetKbdType())
        let commandModifier = UInt32((cmdKey >> 8) & 0xFF)
        return layout.withUnsafeBytes { raw -> CGKeyCode? in
            guard let base = raw.baseAddress?.assumingMemoryBound(to: UCKeyboardLayout.self) else { return nil }
            for code in keyCodes {
                var deadKeys: UInt32 = 0
                var length = 0
                var characters = [UniChar](repeating: 0, count: 4)
                let status = UCKeyTranslate(base, UInt16(code), UInt16(kUCKeyActionDown), commandModifier, keyboardType,
                                            OptionBits(kUCKeyTranslateNoDeadKeysBit), &deadKeys, characters.count, &length, &characters)
                if status == noErr, length == 1, String(utf16CodeUnits: characters, count: length) == String(character) {
                    return CGKeyCode(code)
                }
            }
            return nil
        }
    }
}
