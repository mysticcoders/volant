import Foundation
import Security
import CryptoKit

/// A per-device AES key for clipboard history, created once and held in the Keychain (this device only, unlocked only).
enum KeychainKey {
    // Storage compatibility, not the app identity. Reuse the existing AES key after the bundle rename.
    private static let service = "com.mysticcoders.vey.clipboard-key"
    private static let account = "aes-256-gcm"

    static func load() -> SymmetricKey? {
        if let existing = read() { return existing }
        let key = SymmetricKey(size: .bits256)
        return store(key) ? key : nil
    }

    private static func read() -> SymmetricKey? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess, let data = item as? Data else { return nil }
        return SymmetricKey(data: data)
    }

    private static func store(_ key: SymmetricKey) -> Bool {
        let data = key.withUnsafeBytes { Data($0) }
        let attrs: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
            kSecValueData as String: data,
        ]
        return SecItemAdd(attrs as CFDictionary, nil) == errSecSuccess
    }
}
