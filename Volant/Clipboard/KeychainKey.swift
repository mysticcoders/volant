import Foundation
import Security
import CryptoKit

/// Reuse the original clipboard key. A failed read must never replace it.
enum KeychainKey {
    private static let service = "com.mysticcoders.vey.clipboard-key"
    private static let account = "aes-256-gcm"

    enum Failure: Error, Equatable {
        case access(OSStatus)
        case missingHistoryKey
        case invalidKey
    }

    struct Access {
        var read: () -> (OSStatus, Data?)
        var add: (Data) -> OSStatus
        static let live = Access(read: {
            let query: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: service,
                kSecAttrAccount as String: account,
                kSecReturnData as String: true,
            ]
            var item: CFTypeRef?
            let status = SecItemCopyMatching(query as CFDictionary, &item)
            return (status, item as? Data)
        }, add: { data in
            let attrs: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: service,
                kSecAttrAccount as String: account,
                kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
                kSecValueData as String: data,
            ]
            return SecItemAdd(attrs as CFDictionary, nil)
        })
    }

    static func load(createIfMissing: Bool, access: Access = .live) throws -> SymmetricKey {
        let (status, data) = access.read()
        if status == errSecSuccess { return try decode(data) }
        guard status == errSecItemNotFound else { throw Failure.access(status) }
        guard createIfMissing else { throw Failure.missingHistoryKey }
        let key = SymmetricKey(size: .bits256)
        let added = access.add(key.withUnsafeBytes { Data($0) })
        if added == errSecSuccess { return key }
        // Another instance may have created it between our read and add. Never overwrite.
        if added == errSecDuplicateItem {
            let (status, data) = access.read()
            guard status == errSecSuccess else { throw Failure.access(status) }
            return try decode(data)
        }
        throw Failure.access(added)
    }

    private static func decode(_ data: Data?) throws -> SymmetricKey {
        guard let data, data.count == 32 else { throw Failure.invalidKey }
        return SymmetricKey(data: data)
    }
}
