import Foundation

/// The signed index of extensions Volant can install, published from mysticcoders/volant-extensions to
/// GitHub Pages. `catalog.json` is signed with Ed25519 in that repository's CI; Volant holds the public
/// key and rejects an index whose signature fails or whose sequence is lower than one it already accepted.
///
/// A package is `manifest.json`, its module and optionally a small WebP icon, at paths Volant derives
/// from the listing's ID, version and file names, so nothing in the index chooses where a file is
/// written and there is no archive to extract. Every downloaded byte must match the listed size and
/// SHA-256, and the manifest must agree with the listing. Installing never enables or runs an extension.
public struct ExtensionCatalog: Codable, Equatable {
    public static let host = "mysticcoders.github.io"
    public static let baseURL = URL(string: "https://mysticcoders.github.io/volant-extensions/")!
    public static let indexPath = "catalog.json"
    public static let signaturePath = "catalog.json.sig"
    public static let maximumIndexBytes = 256 * 1024
    public static let maximumSignatureBytes = 1024
    public static let maximumManifestBytes = 32_768
    public static let maximumModuleBytes = 2_097_152
    public static let maximumListings = 64

    public var format: Int
    public var sequence: Int
    public var generated: String
    public var revision: String
    public var extensions: [Listing]

    public init(format: Int, sequence: Int, generated: String, revision: String, extensions: [Listing]) {
        self.format = format; self.sequence = sequence; self.generated = generated; self.revision = revision; self.extensions = extensions
    }

    /// One downloadable file's expected size and lowercase SHA-256.
    public struct File: Codable, Hashable {
        public var sha256: String
        public var size: Int
        public init(sha256: String, size: Int) { self.sha256 = sha256; self.size = size }
    }

    /// One installable extension. The manifest fields repeated here let Settings describe permissions
    /// before anything is downloaded; `verify` requires the downloaded manifest to agree with them.
    public struct Listing: Codable, Hashable, Identifiable {
        public var id: String
        public var name: String
        public var version: String
        public var module: String
        public var summary: String
        public var publisher: String
        public var license: String
        public var notes: String?
        public var abiVersion: Int
        public var capabilities: [String]
        public var hosts: [String]
        public var source: String
        public var manifest: File
        public var moduleFile: File
        /// The icon's file name and entry, when the extension has one. Older Volant versions ignore both.
        public var icon: String?
        public var iconFile: File?
        /// Whether the extension keeps saved data on this Mac; must match the manifest.
        public var storage: Bool?

        public init(id: String, name: String, version: String, module: String, summary: String, publisher: String, license: String,
                    notes: String? = nil, abiVersion: Int = 1, capabilities: [String] = [], hosts: [String] = [], source: String,
                    manifest: File, moduleFile: File, icon: String? = nil, iconFile: File? = nil) {
            self.id = id; self.name = name; self.version = version; self.module = module; self.summary = summary
            self.publisher = publisher; self.license = license; self.notes = notes; self.abiVersion = abiVersion
            self.capabilities = capabilities; self.hosts = hosts; self.source = source; self.manifest = manifest; self.moduleFile = moduleFile
            self.icon = icon; self.iconFile = iconFile
        }

        public var manifestPath: String { "packages/\(id)/\(version)/manifest.json" }
        public var modulePath: String { "packages/\(id)/\(version)/\(module)" }
        public var iconPath: String? { icon.map { "packages/\(id)/\(version)/\($0)" } }
        public var sourceURL: URL? { URL(string: source) }

        /// Checks every field Volant relies on: an ID that is also a safe folder name, path-safe version
        /// and module names, bounded text, known capabilities, valid hosts and plausible file entries.
        public func validate() throws {
            guard ExtensionCatalog.isSafeID(id), ExtensionCatalog.isSafeVersion(version), ExtensionCatalog.isSafeModule(module),
                  (1...128).contains(name.count), (1...300).contains(summary.count), (1...80).contains(publisher.count),
                  (1...64).contains(license.count), (notes?.count ?? 0) <= 600, [1, 2].contains(abiVersion),
                  abiVersion != 2 || capabilities.isEmpty,
                  Set(capabilities).isSubset(of: ExtensionManifest.knownCapabilities), Set(capabilities).count == capabilities.count,
                  hosts.count <= ExtensionNetwork.maximumHosts, Set(hosts).count == hosts.count, hosts.allSatisfy(ExtensionNetwork.isValidHost),
                  let url = URL(string: source), url.scheme == "https", url.host != nil, source.count <= 512,
                  ExtensionCatalog.isValid(manifest, maximum: ExtensionCatalog.maximumManifestBytes),
                  ExtensionCatalog.isValid(moduleFile, maximum: ExtensionCatalog.maximumModuleBytes),
                  ExtensionManifest.isValidIcon(icon, sha256: iconFile?.sha256), icon == nil || iconFile != nil,
                  iconFile.map({ ExtensionCatalog.isValid($0, maximum: ExtensionManifest.maximumIconBytes) }) ?? true else {
                throw ExtensionCatalogError.invalidIndex
            }
        }

        /// Checks downloaded bytes against this listing and returns the manifest they contain. Sizes and
        /// hashes must match the signed index, the manifest must be valid and agree with the listing, and
        /// the module must hash to the manifest's pinned SHA-256 and declare bounded memory.
        public func verify(manifest manifestData: Data, module moduleData: Data, icon iconData: Data? = nil,
                           sha256: (Data) -> String) throws -> ExtensionManifest {
            guard manifestData.count == manifest.size, sha256(manifestData) == manifest.sha256 else {
                throw ExtensionCatalogError.mismatch("\(name)’s manifest does not match the signed catalog.")
            }
            guard moduleData.count == moduleFile.size, sha256(moduleData) == moduleFile.sha256 else {
                throw ExtensionCatalogError.mismatch("\(name)’s module does not match the signed catalog.")
            }
            guard let decoded = try? JSONDecoder().decode(ExtensionManifest.self, from: manifestData), (try? decoded.validate()) != nil else {
                throw ExtensionCatalogError.mismatch("\(name)’s manifest is not valid.")
            }
            guard decoded.id == id, decoded.name == name, decoded.version == version, decoded.module == module,
                  (decoded.abiVersion ?? 1) == abiVersion, decoded.capabilities == capabilities, decoded.declaredHosts == hosts,
                  decoded.sha256?.lowercased() == moduleFile.sha256, decoded.icon == icon, decoded.iconSha256 == iconFile?.sha256,
                  decoded.usesStorage == (storage == true) else {
                throw ExtensionCatalogError.mismatch("\(name)’s manifest does not agree with its catalog listing.")
            }
            if let iconFile {
                guard let iconData, iconData.count == iconFile.size, sha256(iconData) == iconFile.sha256,
                      ExtensionManifest.looksLikeWebP(iconData) else {
                    throw ExtensionCatalogError.mismatch("\(name)’s icon does not match the signed catalog.")
                }
            }
            do { try ExtensionMemory.validate(moduleData) } catch {
                throw ExtensionCatalogError.mismatch("\(name)’s module must declare bounded memory.")
            }
            return decoded
        }
    }

    /// Decodes an index after `verify` accepts its signature, then rejects unknown formats, rollback
    /// below `minimumSequence`, duplicate IDs and any invalid listing.
    public static func decode(_ index: Data, signature: Data, minimumSequence: Int, verify: (_ signature: Data, _ index: Data) -> Bool) throws -> ExtensionCatalog {
        guard index.count <= maximumIndexBytes, signature.count <= maximumSignatureBytes else { throw ExtensionCatalogError.invalidIndex }
        guard let raw = Data(base64Encoded: signature, options: .ignoreUnknownCharacters), raw.count == 64, verify(raw, index) else {
            throw ExtensionCatalogError.badSignature
        }
        guard let catalog = try? JSONDecoder().decode(ExtensionCatalog.self, from: index), catalog.format == 1, catalog.sequence > 0,
              catalog.revision.count == 40, catalog.revision.allSatisfy({ $0.isASCII && $0.isHexDigit }), catalog.generated.count <= 64,
              catalog.extensions.count <= maximumListings, Set(catalog.extensions.map(\.id)).count == catalog.extensions.count else {
            throw ExtensionCatalogError.invalidIndex
        }
        guard catalog.sequence >= minimumSequence else { throw ExtensionCatalogError.rollback }
        for listing in catalog.extensions { try listing.validate() }
        return catalog
    }

    /// The URL for a catalog file path, or nil unless the path is the index, its signature or a package
    /// file shaped `packages/<id>/<version>/<file>`. The fetch helper checks this again before fetching.
    public static func url(for path: String) -> URL? {
        let parts = path.split(separator: "/", omittingEmptySubsequences: false).map(String.init)
        let allowed = path == indexPath || path == signaturePath ||
            (parts.count == 4 && parts[0] == "packages" && isSafeID(parts[1]) && isSafeVersion(parts[2]) &&
                (parts[3] == "manifest.json" || isSafeModule(parts[3]) || ExtensionManifest.isSafeIconName(parts[3])))
        return allowed ? URL(string: path, relativeTo: baseURL)?.absoluteURL : nil
    }

    /// Lowercase dotted labels, also used as the installed folder name.
    static func isSafeID(_ id: String) -> Bool {
        let labels = id.split(separator: ".", omittingEmptySubsequences: false)
        return id.count <= 128 && labels.count >= 2 && labels.allSatisfy { label in
            !label.isEmpty && label.allSatisfy { $0.isASCII && ($0.isLowercase || $0.isNumber || $0 == "-") }
        }
    }

    static func isSafeVersion(_ version: String) -> Bool {
        (1...32).contains(version.count) && version != "." && version != ".." && version.contains(where: { $0.isASCII && ($0.isLetter || $0.isNumber) }) &&
            version.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || ".+-".contains($0)) }
    }

    static func isSafeModule(_ module: String) -> Bool {
        let stem = module.dropLast(5)
        return module.hasSuffix(".wasm") && (1...64).contains(stem.count) &&
            stem.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "_" || $0 == "-") }
    }

    static func isValid(_ file: File, maximum: Int) -> Bool {
        (1...maximum).contains(file.size) && file.sha256.count == 64 &&
            file.sha256.allSatisfy { $0.isASCII && $0.isHexDigit && !$0.isUppercase }
    }
}

/// Where an installed extension came from, written beside it as `.volant-catalog.json` when the catalog
/// installs it. It is a record for Settings and support, not a grant: approval still comes from the
/// owner and is bound to the manifest.
public struct ExtensionCatalogOrigin: Codable, Equatable {
    public static let fileName = ".volant-catalog.json"
    public var id: String
    public var version: String
    public var sequence: Int
    public var revision: String
    public var source: String
    public init(id: String, version: String, sequence: Int, revision: String, source: String) {
        self.id = id; self.version = version; self.sequence = sequence; self.revision = revision; self.source = source
    }
}

public enum ExtensionCatalogError: Error, LocalizedError, Equatable {
    case badSignature, invalidIndex, rollback, unavailable(String), mismatch(String), conflict(String)
    public var errorDescription: String? {
        switch self {
        case .badSignature: return "The extension catalog’s signature is not valid. Nothing was installed."
        case .invalidIndex: return "The extension catalog is not in a format this version of Volant can read."
        case .rollback: return "The extension catalog is older than one Volant already accepted, so it was not used."
        case .unavailable(let detail): return "Couldn’t reach the extension catalog. \(detail)"
        case .mismatch(let detail), .conflict(let detail): return detail
        }
    }
}
