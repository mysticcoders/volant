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
/// validly signed catalog cannot be replayed to offer superseded versions. It is per Mac and not synced.
enum ExtensionCatalogState {
    static var defaultURL: URL { Preferences.supportDirectory.appendingPathComponent("extension-catalog.json") }

    static func sequence(at url: URL) -> Int {
        guard let data = try? Data(contentsOf: url), let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return 0 }
        return object["sequence"] as? Int ?? 0
    }

    static func record(_ sequence: Int, at url: URL) throws {
        guard sequence > self.sequence(at: url) else { return }
        try JSONSerialization.data(withJSONObject: ["sequence": sequence], options: [.sortedKeys]).write(to: url, options: .atomic)
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
    /// accepted sequence.
    func load(completion: @escaping (Result<ExtensionCatalog, Error>) -> Void) {
        fetchFile(ExtensionCatalog.indexPath, ExtensionCatalog.maximumIndexBytes) { index in
            fetchFile(ExtensionCatalog.signaturePath, ExtensionCatalog.maximumSignatureBytes) { signature in
                let result = Result<ExtensionCatalog, Error> {
                    let key = publicKey
                    let catalog = try ExtensionCatalog.decode(try index.get(), signature: try signature.get(),
                                                              minimumSequence: ExtensionCatalogState.sequence(at: stateURL)) {
                        ExtensionCatalogKey.verify($0, $1, publicKey: key)
                    }
                    try? ExtensionCatalogState.record(catalog.sequence, at: stateURL)
                    return catalog
                }
                DispatchQueue.main.async { completion(result) }
            }
        }
    }

    /// Downloads a listing's manifest and module. The caller verifies them while installing.
    func download(_ listing: ExtensionCatalog.Listing, completion: @escaping (Result<(manifest: Data, module: Data), Error>) -> Void) {
        fetchFile(listing.manifestPath, listing.manifest.size) { manifest in
            fetchFile(listing.modulePath, listing.moduleFile.size) { module in
                let result = Result<(manifest: Data, module: Data), Error> { (try manifest.get(), try module.get()) }
                DispatchQueue.main.async { completion(result) }
            }
        }
    }
}
