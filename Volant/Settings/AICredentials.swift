import Foundation
import Security

/// Keys are never part of configuration/backup JSON, labels, errors or logs.
struct AICredentials {
    var read: (String) throws -> String?
    var write: (String, String?) throws -> Void
    static let keychain = AICredentials(read: { account in
        var query = base(account); query[kSecReturnData as String] = true
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = result as? Data, let key = String(data: data, encoding: .utf8) else { throw CredentialError.unavailable }
        return key
    }, write: { account, key in
        let query = base(account)
        guard let key, !key.isEmpty else {
            let status = SecItemDelete(query as CFDictionary)
            guard status == errSecSuccess || status == errSecItemNotFound else { throw CredentialError.unavailable }
            return
        }
        guard key.utf8.count <= 8192, !key.contains(where: { $0.isWhitespace }) else { throw CredentialError.invalid }
        let value = Data(key.utf8)
        let status = SecItemUpdate(query as CFDictionary, [kSecValueData as String: value] as CFDictionary)
        if status == errSecItemNotFound {
            var item = query; item[kSecValueData as String] = value
            item[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
            guard SecItemAdd(item as CFDictionary, nil) == errSecSuccess else { throw CredentialError.unavailable }
        } else if status != errSecSuccess { throw CredentialError.unavailable }
    })
    private static func base(_ account: String) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: "com.mysticcoders.volant.ai", kSecAttrAccount as String: account]
    }
    enum CredentialError: Error, LocalizedError {
        case unavailable, invalid
        var errorDescription: String? { self == .invalid ? "Enter a valid API key without spaces." : "Couldn’t access the API key in Keychain. Your saved key was not replaced." }
    }
}
