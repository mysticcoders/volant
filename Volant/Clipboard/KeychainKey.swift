import Foundation
import Security
import CryptoKit

/// Reuse the original clipboard key. A failed read must never replace it.
enum KeychainKey {
    private static let service = "com.mysticcoders.volant.clipboard-key"
    /// Where releases up to 0.3.14 kept the key, before the app was renamed from Vey.
    private static let legacyService = "com.mysticcoders.vey.clipboard-key"
    private static let account = "aes-256-gcm"

    enum Failure: Error, Equatable {
        case access(OSStatus)
        case missingHistoryKey
        case invalidKey
    }

    struct Access {
        var read: () -> (OSStatus, Data?)
        var add: (Data) -> OSStatus
        var readLegacy: () -> (OSStatus, Data?) = { (errSecItemNotFound, nil) }
        var deleteLegacy: () -> OSStatus = { errSecSuccess }
        static let live = Access(read: { copy(service) }, add: { data in
            let attrs: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: service,
                kSecAttrAccount as String: account,
                kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
                kSecValueData as String: data,
            ]
            return SecItemAdd(attrs as CFDictionary, nil)
        }, readLegacy: { copy(legacyService) }, deleteLegacy: {
            let query: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: legacyService,
                kSecAttrAccount as String: account,
            ]
            return SecItemDelete(query as CFDictionary)
        })

        private static func copy(_ service: String) -> (OSStatus, Data?) {
            let query: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: service,
                kSecAttrAccount as String: account,
                kSecReturnData as String: true,
            ]
            var item: CFTypeRef?
            let status = SecItemCopyMatching(query as CFDictionary, &item)
            return (status, item as? Data)
        }
    }

    static func load(createIfMissing: Bool, access: Access = .live) throws -> SymmetricKey {
        let (status, data) = access.read()
        if status == errSecSuccess { return try decode(data) }
        guard status == errSecItemNotFound else { throw Failure.access(status) }
        let (legacyStatus, legacyData) = access.readLegacy()
        if legacyStatus == errSecSuccess { return adopt(try decode(legacyData), access: access) }
        guard legacyStatus == errSecItemNotFound else { throw Failure.access(legacyStatus) }
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

    /// Copies the legacy key to the current item and removes the legacy one only once the current
    /// item reads back with the same bytes. Otherwise it keeps using the legacy key, which still
    /// decrypts the history, and tries again on a later launch.
    private static func adopt(_ legacy: SymmetricKey, access: Access) -> SymmetricKey {
        let bytes = legacy.withUnsafeBytes { Data($0) }
        let added = access.add(bytes)
        guard added == errSecSuccess || added == errSecDuplicateItem else { return legacy }
        let (status, data) = access.read()
        if status == errSecSuccess, data == bytes { _ = access.deleteLegacy() }
        return legacy
    }

    private static func decode(_ data: Data?) throws -> SymmetricKey {
        guard let data, data.count == 32 else { throw Failure.invalidKey }
        return SymmetricKey(data: data)
    }
}
