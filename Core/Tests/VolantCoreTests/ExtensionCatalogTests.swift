import Foundation
import XCTest

@testable import VolantCore

/// The catalog boundary: signature and rollback checks on the index, which listings and paths are
/// acceptable, and whether downloaded package bytes agree with the signed listing. Signing and hashing
/// are injected; the app's CryptoKit verifier has its own tests.
final class ExtensionCatalogTests: XCTestCase {
    private let module = Data([0, 97, 115, 109, 1, 0, 0, 0, 5, 4, 1, 1, 1, 1])
    private let signature = Data(Data(repeating: 7, count: 64).base64EncodedString().utf8)

    /// A stable 64-character lowercase hex digest for fixtures, without CryptoKit.
    private func hash(_ data: Data) -> String {
        (0..<4).map { seed -> String in
            var value: UInt64 = 0xcbf29ce484222325 &+ UInt64(seed)
            for byte in data { value = (value ^ UInt64(byte)) &* 0x100000001b3 }
            return String(format: "%016llx", value)
        }.joined()
    }

    private func manifestData(_ change: (inout ExtensionManifest) -> Void = { _ in }) throws -> Data {
        var manifest = ExtensionManifest(id: "community.fictional.reader", name: "Fictional Reader", version: "1.0.0", module: "reader.wasm",
                                         capabilities: [], timeoutSeconds: 2, sha256: hash(module), hosts: ["news.example.com"], output: "items")
        change(&manifest)
        let encoder = JSONEncoder(); encoder.outputFormatting = .sortedKeys
        return try encoder.encode(manifest)
    }

    private func listing(manifest: Data? = nil) throws -> ExtensionCatalog.Listing {
        let data = try manifest ?? manifestData()
        return ExtensionCatalog.Listing(id: "community.fictional.reader", name: "Fictional Reader", version: "1.0.0", module: "reader.wasm",
                                        summary: "Fictional stories.", publisher: "Fictional Publisher", license: "MIT",
                                        hosts: ["news.example.com"], source: "https://example.com/fictional/reader",
                                        manifest: .init(sha256: hash(data), size: data.count), moduleFile: .init(sha256: hash(module), size: module.count))
    }

    private func index(sequence: Int = 5, format: Int = 1, listings: [ExtensionCatalog.Listing]) throws -> Data {
        try JSONEncoder().encode(ExtensionCatalog(format: format, sequence: sequence, generated: "2026-10-12T00:00:00Z",
                                                  revision: String(repeating: "a", count: 40), extensions: listings))
    }

    private func decode(_ data: Data, minimum: Int = 0, valid: Bool = true) throws -> ExtensionCatalog {
        try ExtensionCatalog.decode(data, signature: signature, minimumSequence: minimum) { raw, _ in valid && raw.count == 64 }
    }

    func testSignedCurrentIndexDecodes() throws {
        let catalog = try decode(try index(listings: [try listing()]))
        XCTAssertEqual(catalog.extensions.map(\.id), ["community.fictional.reader"])
        XCTAssertEqual(catalog.sequence, 5)
        XCTAssertNoThrow(try decode(try index(listings: [try listing()]), minimum: 5))
    }

    func testBadSignatureRollbackAndUnknownFormatAreRejected() throws {
        let data = try index(listings: [try listing()])
        XCTAssertThrowsError(try decode(data, valid: false)) { XCTAssertEqual($0 as? ExtensionCatalogError, .badSignature) }
        XCTAssertThrowsError(try ExtensionCatalog.decode(data, signature: Data("c2hvcnQ=".utf8), minimumSequence: 0) { _, _ in true }) {
            XCTAssertEqual($0 as? ExtensionCatalogError, .badSignature)
        }
        XCTAssertThrowsError(try decode(data, minimum: 6)) { XCTAssertEqual($0 as? ExtensionCatalogError, .rollback) }
        XCTAssertThrowsError(try decode(try index(format: 2, listings: []))) { XCTAssertEqual($0 as? ExtensionCatalogError, .invalidIndex) }
        XCTAssertThrowsError(try decode(Data("not json".utf8))) { XCTAssertEqual($0 as? ExtensionCatalogError, .invalidIndex) }
        XCTAssertThrowsError(try decode(Data(count: ExtensionCatalog.maximumIndexBytes + 1)))
    }

    func testDuplicateAndUnsafeListingsAreRejected() throws {
        let good = try listing()
        XCTAssertThrowsError(try decode(try index(listings: [good, good])))
        let unsafe: [(inout ExtensionCatalog.Listing) -> Void] = [
            { $0.id = "../escape" }, { $0.id = "Community.Upper" }, { $0.id = "single" }, { $0.id = "community..reader" },
            { $0.id = "community.reader/../x" }, { $0.version = ".." }, { $0.version = "1/2" }, { $0.version = "" },
            { $0.module = "../reader.wasm" }, { $0.module = "reader.js" }, { $0.module = "sub/reader.wasm" }, { $0.module = ".wasm" },
            { $0.moduleFile.size = ExtensionCatalog.maximumModuleBytes + 1 }, { $0.moduleFile.size = 0 },
            { $0.manifest.size = ExtensionCatalog.maximumManifestBytes + 1 }, { $0.moduleFile.sha256 = String(repeating: "A", count: 64) },
            { $0.manifest.sha256 = "abc" }, { $0.source = "http://example.com/reader" }, { $0.source = "file:///etc/passwd" },
            { $0.capabilities = ["filesystem"] }, { $0.hosts = ["*.example.com"] }, { $0.abiVersion = 3 },
            { $0.abiVersion = 2; $0.capabilities = ["log"] }, { $0.summary = String(repeating: "x", count: 301) }, { $0.name = "" },
        ]
        for (offset, change) in unsafe.enumerated() {
            var bad = good; change(&bad)
            XCTAssertThrowsError(try decode(try index(listings: [bad])), "case \(offset)") {
                XCTAssertEqual($0 as? ExtensionCatalogError, .invalidIndex, "case \(offset)")
            }
        }
    }

    func testOnlyFixedCatalogPathsResolve() throws {
        XCTAssertEqual(ExtensionCatalog.url(for: "catalog.json")?.absoluteString, "https://mysticcoders.github.io/volant-extensions/catalog.json")
        XCTAssertEqual(ExtensionCatalog.url(for: "catalog.json.sig")?.host, ExtensionCatalog.host)
        let listing = try listing()
        XCTAssertEqual(ExtensionCatalog.url(for: listing.modulePath)?.absoluteString,
                       "https://mysticcoders.github.io/volant-extensions/packages/community.fictional.reader/1.0.0/reader.wasm")
        XCTAssertNotNil(ExtensionCatalog.url(for: listing.manifestPath))
        for path in ["", "/catalog.json", "../catalog.json", "packages/../catalog.json", "packages/community.reader/../x.wasm",
                     "packages/community.reader/1/../../x.wasm", "packages/community.reader/1/notes.txt", "packages/community.reader/1/x.wasm/extra",
                     "https://evil.example.com/catalog.json", "//evil.example.com/catalog.json", "catalog.json?x=1", "catalog.json#x",
                     "packages/Community.Reader/1/x.wasm", "packages/community.reader/1/x%2F.wasm", "other.json"] {
            XCTAssertNil(ExtensionCatalog.url(for: path), path)
        }
    }

    func testDownloadedBytesMustMatchTheSignedListing() throws {
        let manifest = try manifestData()
        let listing = try listing(manifest: manifest)
        XCTAssertEqual(try listing.verify(manifest: manifest, module: module, sha256: hash).declaredHosts, ["news.example.com"])
        XCTAssertThrowsError(try listing.verify(manifest: manifest + Data([32]), module: module, sha256: hash))
        var tampered = module; tampered[13] = 2
        XCTAssertThrowsError(try listing.verify(manifest: manifest, module: tampered, sha256: hash))
        XCTAssertThrowsError(try listing.verify(manifest: manifest, module: module + Data([0]), sha256: hash))
    }

    func testManifestMustAgreeWithItsListing() throws {
        let disagreements: [(inout ExtensionManifest) -> Void] = [
            { $0.id = "community.fictional.other" }, { $0.version = "2.0.0" }, { $0.name = "Other" },
            { $0.hosts = ["news.example.com", "tracker.example.com"] }, { $0.capabilities = ["clipboard.write"] },
            { $0.sha256 = String(repeating: "b", count: 64) }, { $0.module = "other.wasm" }, { $0.output = nil },
        ]
        for (offset, change) in disagreements.enumerated() {
            let manifest = try manifestData(change)
            let listing = try listing(manifest: manifest)
            XCTAssertThrowsError(try listing.verify(manifest: manifest, module: module, sha256: hash), "case \(offset)")
        }
    }

    func testUnboundedMemoryModuleIsRejectedEvenWhenHashesMatch() throws {
        let unbounded = Data([0, 97, 115, 109, 1, 0, 0, 0, 5, 3, 1, 0, 1])
        let manifest = try manifestData { $0.sha256 = self.hash(unbounded) }
        var listing = try listing(manifest: manifest)
        listing.moduleFile = .init(sha256: hash(unbounded), size: unbounded.count)
        XCTAssertThrowsError(try listing.verify(manifest: manifest, module: unbounded, sha256: hash))
    }
}
