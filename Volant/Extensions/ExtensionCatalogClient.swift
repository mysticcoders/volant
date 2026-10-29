import CryptoKit
import Foundation
import VolantCore

/// Checks catalog index signatures. The private half of this Ed25519 key exists only as a GitHub Actions
/// secret in mysticcoders/volant-extensions, whose CI signs each published catalog.json.
enum ExtensionCatalogKey {
    static let publicKey = "712VYombBHulfKla/3qDhiQI/jZcosNTB/IDqPc63Y4="

    static func verify(_ signature: Data, _ index: Data, publicKey: String = publicKey) -> Bool {
        guard let raw = Data(base64Encoded: publicKey), let key = try? Curve25519.Signing.PublicKey(rawRepresentation: raw) else { return false }
        return key.isValidSignature(signature, for: index)
    }
}

/// The highest catalog sequence this Mac accepted, kept in its own file beside config.json so an older,
/// validly signed catalog cannot be replayed to offer superseded versions, and the revocations from the
/// newest catalog applied, so withdrawn extensions stay off without checking the catalog again. It is per
/// Mac and not synced. Each write keeps the other fields.
enum ExtensionCatalogState {
    static var defaultURL: URL { Preferences.supportDirectory.appendingPathComponent("extension-catalog.json") }

    /// The state file that belongs beside a config file.
    static func url(besideConfig configURL: URL) -> URL {
        configURL.deletingLastPathComponent().appendingPathComponent("extension-catalog.json")
    }

    static func sequence(at url: URL) -> Int { read(url)["sequence"] as? Int ?? 0 }

    static func record(_ sequence: Int, at url: URL) throws {
        var object = read(url)
        guard sequence > object["sequence"] as? Int ?? 0 else { return }
        object["sequence"] = sequence
        try write(object, to: url)
    }

    /// The revocations last applied, or none when the file is missing or unreadable.
    static func revoked(at url: URL) -> [ExtensionCatalog.Revocation] {
        guard let list = read(url)["revoked"],
              let data = try? JSONSerialization.data(withJSONObject: list) else { return [] }
        return (try? JSONDecoder().decode([ExtensionCatalog.Revocation].self, from: data)) ?? []
    }

    /// Replaces the stored revocations with a catalog's, unless a newer catalog's are already stored.
    static func recordRevocations(_ revoked: [ExtensionCatalog.Revocation], sequence: Int, at url: URL) throws {
        var object = read(url)
        guard sequence >= object["revokedSequence"] as? Int ?? 0 else { return }
        object["revoked"] = try JSONSerialization.jsonObject(with: JSONEncoder().encode(revoked))
        object["revokedSequence"] = sequence
        try write(object, to: url)
    }

    /// When this Mac last accepted a catalog, from any check; nil before the first.
    static func checked(at url: URL) -> Date? {
        (read(url)["checked"] as? Double).map(Date.init(timeIntervalSince1970:))
    }

    static func recordChecked(_ date: Date, at url: URL) throws {
        var object = read(url)
        object["checked"] = date.timeIntervalSince1970
        try write(object, to: url)
    }

    /// The signed index and its signature as last accepted, kept beside the state file so update
    /// notices can be built without contacting the catalog. They are verified again on every read.
    static func indexURL(beside url: URL) -> URL { url.deletingLastPathComponent().appendingPathComponent("extension-catalog-index.json") }
    static func signatureURL(beside url: URL) -> URL { url.deletingLastPathComponent().appendingPathComponent("extension-catalog-index.sig") }

    static func saveIndex(_ index: Data, signature: Data, beside url: URL) throws {
        try index.write(to: indexURL(beside: url), options: .atomic)
        try signature.write(to: signatureURL(beside: url), options: .atomic)
    }

    private static func read(_ url: URL) -> [String: Any] {
        guard let data = try? Data(contentsOf: url), let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return [:] }
        return object
    }

    private static func write(_ object: [String: Any], to url: URL) throws {
        try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]).write(to: url, options: .atomic)
    }
}

/// Loads the signed catalog and downloads packages. Volant itself has no network access: `fetchFile`
/// asks VolantFetchHost for one fixed catalog path. Fixtures replace `fetchFile` and `publicKey`.
/// Completions arrive on the main queue.
struct ExtensionCatalogClient {
    var fetchFile: (_ path: String, _ maximumBytes: Int, _ completion: @escaping (Result<Data, Error>) -> Void) -> Void
    var publicKey = ExtensionCatalogKey.publicKey
    var stateURL = ExtensionCatalogState.defaultURL

    static let live = ExtensionCatalogClient(fetchFile: ExtensionFetcher.catalogFile)

    /// Fetches the index and its signature, verifies the signature, rejects rollback, and records the
    /// accepted sequence, the time and the signed index itself for `cached()`.
    func load(completion: @escaping (Result<ExtensionCatalog, Error>) -> Void) {
        fetchFile(ExtensionCatalog.indexPath, ExtensionCatalog.maximumIndexBytes) { index in
            fetchFile(ExtensionCatalog.signaturePath, ExtensionCatalog.maximumSignatureBytes) { signature in
                let result = Result<ExtensionCatalog, Error> {
                    let key = publicKey
                    let indexData = try index.get(), signatureData = try signature.get()
                    let catalog = try ExtensionCatalog.decode(indexData, signature: signatureData,
                                                              minimumSequence: ExtensionCatalogState.sequence(at: stateURL)) {
                        ExtensionCatalogKey.verify($0, $1, publicKey: key)
                    }
                    try? ExtensionCatalogState.record(catalog.sequence, at: stateURL)
                    try? ExtensionCatalogState.saveIndex(indexData, signature: signatureData, beside: stateURL)
                    try? ExtensionCatalogState.recordChecked(Date(), at: stateURL)
                    return catalog
                }
                DispatchQueue.main.async { completion(result) }
            }
        }
    }

    /// The catalog last accepted on this Mac, read from disk without contacting the catalog: nil when
    /// none was saved, or when the saved copy is too large, fails its signature or is older than the
    /// recorded sequence.
    func cached() -> ExtensionCatalog? {
        let indexURL = ExtensionCatalogState.indexURL(beside: stateURL), signatureURL = ExtensionCatalogState.signatureURL(beside: stateURL)
        guard (try? indexURL.resourceValues(forKeys: [.fileSizeKey]).fileSize).flatMap({ $0 }) ?? .max <= ExtensionCatalog.maximumIndexBytes,
              let index = try? Data(contentsOf: indexURL), let signature = try? Data(contentsOf: signatureURL) else { return nil }
        let key = publicKey
        return try? ExtensionCatalog.decode(index, signature: signature, minimumSequence: ExtensionCatalogState.sequence(at: stateURL)) {
            ExtensionCatalogKey.verify($0, $1, publicKey: key)
        }
    }

    /// Downloads a listing's manifest, module and icon, if it has one. The caller verifies them while installing.
    func download(_ listing: ExtensionCatalog.Listing,
                  completion: @escaping (Result<(manifest: Data, module: Data, icon: Data?), Error>) -> Void) {
        fetchFile(listing.manifestPath, listing.manifest.size) { manifest in
            fetchFile(listing.modulePath, listing.moduleFile.size) { module in
                let finish = { (icon: Result<Data, Error>?) in
                    let result = Result<(manifest: Data, module: Data, icon: Data?), Error> {
                        (try manifest.get(), try module.get(), try icon?.get())
                    }
                    DispatchQueue.main.async { completion(result) }
                }
                guard let iconPath = listing.iconPath, let iconFile = listing.iconFile else { finish(nil); return }
                fetchFile(iconPath, iconFile.size) { finish($0) }
            }
        }
    }
}
