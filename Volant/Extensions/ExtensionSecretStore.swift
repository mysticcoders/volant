import Foundation
import Security
import VolantCore

/// Tokens that extensions declare (see `ExtensionSecret`), kept only in the Keychain under this Mac's
/// login, one item per extension and secret. They never enter config.json, backups, iCloud sync, logs or
/// a module's input; Volant reads one only to hand it to the fetch helper as a header for its host.
struct ExtensionSecretStore {
    var read: (String) throws -> String?
    var write: (String, String?) throws -> Void

    static func account(_ extensionID: String, _ secret: ExtensionSecret) -> String { extensionID + "/" + secret.id }

    static let keychain = ExtensionSecretStore(read: { account in
        var query = base(account); query[kSecReturnData as String] = true
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = result as? Data, let value = String(data: data, encoding: .utf8) else { throw SecretError.unavailable }
        return value
    }, write: { account, value in
        let query = base(account)
        guard let value else {
            let status = SecItemDelete(query as CFDictionary)
            guard status == errSecSuccess || status == errSecItemNotFound else { throw SecretError.unavailable }
            return
        }
        guard ExtensionSecret.isValidValue(value) else { throw SecretError.invalid }
        let data = Data(value.utf8)
        let status = SecItemUpdate(query as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if status == errSecItemNotFound {
            var item = query; item[kSecValueData as String] = data
            item[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
            guard SecItemAdd(item as CFDictionary, nil) == errSecSuccess else { throw SecretError.unavailable }
        } else if status != errSecSuccess { throw SecretError.unavailable }
    })

    /// A store that keeps values in memory, for tests.
    static func memory() -> ExtensionSecretStore {
        final class Box { var values: [String: String] = [:] }
        let box = Box()
        return ExtensionSecretStore(read: { box.values[$0] }, write: { account, value in
            if let value { guard ExtensionSecret.isValidValue(value) else { throw SecretError.invalid } }
            box.values[account] = value
        })
    }

    private static func base(_ account: String) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: "com.mysticcoders.volant.extensions", kSecAttrAccount as String: account]
    }

    enum SecretError: Error, LocalizedError {
        case unavailable, invalid
        var errorDescription: String? {
            self == .invalid ? String(localized: "Enter the token without spaces.", comment: "Error for an extension access token") : String(localized: "Couldn’t access the extension’s token in Keychain. The saved token was not replaced.")
        }
    }
}
