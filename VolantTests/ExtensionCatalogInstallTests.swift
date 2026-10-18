import CryptoKit
import XCTest
import VolantCore
@testable import Volant

/// Catalog loading and installation with isolated fixtures: a throwaway signing key, an in-memory
/// "server", and temporary Extensions folders and config files. Nothing touches the network, the owner's
/// Extensions folder or the owner's Trash.
@MainActor
final class ExtensionCatalogInstallTests: XCTestCase {
    private let moduleV1 = Data([0, 97, 115, 109, 1, 0, 0, 0, 5, 4, 1, 1, 1, 1])
    private let moduleV2 = Data([0, 97, 115, 109, 1, 0, 0, 0, 5, 4, 1, 1, 1, 2])
    private var root: URL!
    private var config: URL { root.appendingPathComponent("config.json") }
    private var directory: URL { root.appendingPathComponent("Extensions", isDirectory: true) }

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("catalog-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data(#"{"future":{"keep":true},"extensions":{},"communityExtensionsAllowed":true}"#.utf8).write(to: config)
    }

    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: root) }

    private func package(id: String = "community.fictional.reader", version: String = "1.0.0", module: Data,
                         hosts: [String] = ["news.example.com"]) throws -> (ExtensionCatalog.Listing, Data) {
        let manifest = ExtensionManifest(id: id, name: "Fictional Reader", version: version, module: "reader.wasm", capabilities: [],
                                         timeoutSeconds: 2, sha256: Integrity.sha256(module), hosts: hosts, output: "items")
        let encoder = JSONEncoder(); encoder.outputFormatting = .sortedKeys
        let data = try encoder.encode(manifest)
        let listing = ExtensionCatalog.Listing(id: id, name: "Fictional Reader", version: version, module: "reader.wasm",
                                               summary: "Fictional stories.", publisher: "Fictional Publisher", license: "MIT", hosts: hosts,
                                               source: "https://example.com/fictional/reader",
                                               manifest: .init(sha256: Integrity.sha256(data), size: data.count),
                                               moduleFile: .init(sha256: Integrity.sha256(module), size: module.count))
        return (listing, data)
    }

    private func catalog(_ listings: [ExtensionCatalog.Listing], sequence: Int = 3) -> ExtensionCatalog {
        ExtensionCatalog(format: 1, sequence: sequence, generated: "2026-10-12T00:00:00Z", revision: String(repeating: "c", count: 40), extensions: listings)
    }

    private func manager() -> ExtensionManager {
        let manager = ExtensionManager(configURL: config, directory: directory, dataDirectory: root.appendingPathComponent("ExtensionData")); manager.reload(); return manager
    }

    private func hidden() throws -> [String] {
        try FileManager.default.contentsOfDirectory(atPath: directory.path).filter { $0.hasPrefix(".") }
    }

    /// A client serving `files` from memory, signed with a throwaway key.
    private func client(_ files: [String: Data], key: Curve25519.Signing.PrivateKey, requests: ((String, Int) -> Void)? = nil) -> ExtensionCatalogClient {
        ExtensionCatalogClient(fetchFile: { path, maximum, completion in
            requests?(path, maximum)
            completion(files[path].map { .success($0) } ?? .failure(ExtensionCatalogError.unavailable("Missing \(path).")))
        }, publicKey: key.publicKey.rawRepresentation.base64EncodedString(), stateURL: root.appendingPathComponent("extension-catalog.json"))
    }

    private func signedFiles(_ catalog: ExtensionCatalog, key: Curve25519.Signing.PrivateKey) throws -> [String: Data] {
        let index = try JSONEncoder().encode(catalog)
        return [ExtensionCatalog.indexPath: index,
                ExtensionCatalog.signaturePath: Data(try key.signature(for: index).base64EncodedString().utf8)]
    }

    private func load(_ client: ExtensionCatalogClient) async -> Result<ExtensionCatalog, Error> {
        await withCheckedContinuation { continuation in client.load { continuation.resume(returning: $0) } }
    }

    func testSignedCatalogLoadsAndOlderSequenceIsRefused() async throws {
        let key = Curve25519.Signing.PrivateKey()
        let (listing, _) = try package(module: moduleV1)
        let current = try await load(client(try signedFiles(catalog([listing], sequence: 7), key: key), key: key)).get()
        XCTAssertEqual(current.extensions.map(\.id), [listing.id])
        XCTAssertEqual(ExtensionCatalogState.sequence(at: root.appendingPathComponent("extension-catalog.json")), 7)
        let older = await load(client(try signedFiles(catalog([listing], sequence: 6), key: key), key: key))
        XCTAssertEqual(older.failureValue as? ExtensionCatalogError, .rollback)
        let same = await load(client(try signedFiles(catalog([listing], sequence: 7), key: key), key: key))
        XCTAssertNil(same.failureValue, "The same sequence is accepted again")
    }

    func testTamperedOrForeignSignedCatalogIsRefused() async throws {
        let key = Curve25519.Signing.PrivateKey()
        let (listing, _) = try package(module: moduleV1)
        var files = try signedFiles(catalog([listing]), key: key)
        files[ExtensionCatalog.indexPath]?.append(contentsOf: Data(" ".utf8))
        let tampered = await load(client(files, key: key))
        XCTAssertEqual(tampered.failureValue as? ExtensionCatalogError, .badSignature)
        let foreign = await load(client(try signedFiles(catalog([listing]), key: Curve25519.Signing.PrivateKey()), key: key))
        XCTAssertEqual(foreign.failureValue as? ExtensionCatalogError, .badSignature)
        let index = try JSONEncoder().encode(catalog([listing]))
        XCTAssertFalse(ExtensionCatalogKey.verify(try key.signature(for: index), index), "Only the publisher key verifies production catalogs")
        let missing = await load(client([:], key: key))
        if case .unavailable = missing.failureValue as? ExtensionCatalogError {} else { XCTFail("A missing catalog reads as unavailable") }
    }

    func testDownloadRequestsOnlyDerivedPathsAtListedSizes() async throws {
        let (listing, manifest) = try package(module: moduleV1)
        var requests: [String: Int] = [:]
        let client = client(["packages/community.fictional.reader/1.0.0/manifest.json": manifest,
                             "packages/community.fictional.reader/1.0.0/reader.wasm": moduleV1],
                            key: Curve25519.Signing.PrivateKey()) { requests[$0] = $1 }
        let files = try await withCheckedThrowingContinuation { continuation in client.download(listing) { continuation.resume(with: $0) } }
        XCTAssertEqual(files.module, moduleV1)
        XCTAssertEqual(requests, [listing.manifestPath: manifest.count, listing.modulePath: moduleV1.count])
    }

    func testInstallWritesAtomicallyWithoutEnablingOrRunning() throws {
        let (listing, manifest) = try package(module: moduleV1)
        let manager = manager()
        XCTAssertEqual(ExtensionManager.catalogStatus(listing, installed: manager.extensions), .available)
        let installed = try manager.install(listing, manifest: manifest, module: moduleV1, from: catalog([listing]))
        XCTAssertEqual(installed.directory.lastPathComponent, listing.id)
        XCTAssertFalse(installed.enabled)
        XCTAssertFalse(ExtensionApproval.enabled(installed.manifest, at: config))
        XCTAssertTrue(ExtensionHostApprovals.approved(at: config).isEmpty, "Installing allows no hosts")
        XCTAssertEqual(installed.catalogOrigin?.revision, String(repeating: "c", count: 40))
        XCTAssertEqual(ExtensionManager.catalogStatus(listing, installed: manager.extensions), .installed)
        XCTAssertEqual(try hidden(), [])
        let object = try JSONSerialization.jsonObject(with: Data(contentsOf: config)) as? [String: Any]
        XCTAssertNotNil(object?["future"])
    }

    func testChangedCodeNeedsEnablingAgainButIdenticalReinstallKeepsChoice() throws {
        let (v1, manifest1) = try package(module: moduleV1)
        let manager = manager()
        try manager.install(v1, manifest: manifest1, module: moduleV1, from: catalog([v1]))
        try manager.setEnabled(try XCTUnwrap(manager.extensions.first { $0.id == v1.id }), true)
        try manager.install(v1, manifest: manifest1, module: moduleV1, from: catalog([v1]))
        XCTAssertTrue(try XCTUnwrap(manager.extensions.first { $0.id == v1.id }).enabled, "Same bytes keep the owner's choice")

        let (v2, manifest2) = try package(version: "2.0.0", module: moduleV2, hosts: ["other.example.com"])
        XCTAssertEqual(ExtensionManager.catalogStatus(v2, installed: manager.extensions), .update(from: "1.0.0"))
        let updated = try manager.install(v2, manifest: manifest2, module: moduleV2, from: catalog([v2], sequence: 4))
        XCTAssertEqual(updated.manifest.version, "2.0.0")
        XCTAssertFalse(updated.enabled, "Changed code and hosts need fresh approval")
        XCTAssertFalse(ExtensionHostApprovals.approved(at: config).contains("news.example.com"), "Hosts only the old version used are pruned")
        XCTAssertEqual(try Data(contentsOf: updated.directory.appendingPathComponent("reader.wasm")), moduleV2)
        XCTAssertEqual(try hidden(), [])
    }

    func testUpdateWithoutNewPermissionsStaysEnabled() throws {
        let (v1, manifest1) = try package(module: moduleV1, hosts: ["news.example.com", "api.example.com"])
        let manager = manager()
        try manager.install(v1, manifest: manifest1, module: moduleV1, from: catalog([v1]))
        try manager.setEnabled(try XCTUnwrap(manager.extensions.first { $0.id == v1.id }), true)
        let (v2, manifest2) = try package(version: "2.0.0", module: moduleV2)
        let updated = try manager.install(v2, manifest: manifest2, module: moduleV2, from: catalog([v2], sequence: 4))
        XCTAssertEqual(updated.manifest.version, "2.0.0")
        XCTAssertTrue(updated.enabled, "Changed code that asks for no new access keeps the owner's choice")
        XCTAssertTrue(ExtensionApproval.enabled(updated.manifest, at: config))
        XCTAssertEqual(ExtensionHostApprovals.approved(at: config), ["news.example.com"], "The host only the old version used is pruned")

        let (v3, manifest3) = try package(version: "3.0.0", module: moduleV1)
        let off = manager.extensions.first { $0.id == v1.id }!
        try manager.setEnabled(off, false)
        XCTAssertFalse(try manager.install(v3, manifest: manifest3, module: moduleV1, from: catalog([v3], sequence: 5)).enabled,
                       "An update never turns on an extension the owner turned off")
    }

    func testRevokedCodeIsTurnedOffRefusedAndRemembered() throws {
        let (v1, manifest1) = try package(module: moduleV1)
        let manager = manager()
        try manager.install(v1, manifest: manifest1, module: moduleV1, from: catalog([v1]))
        try manager.setEnabled(try XCTUnwrap(manager.extensions.first), true)
        let revocation = ExtensionCatalog.Revocation(id: v1.id, sha256: v1.moduleFile.sha256, reason: "Sends more than it says.")
        var revoking = catalog([v1], sequence: 4); revoking.revoked = [revocation]

        XCTAssertEqual(manager.applyRevocations(from: revoking).map(\.id), [v1.id])
        let revoked = try XCTUnwrap(manager.extensions.first)
        XCTAssertFalse(revoked.enabled)
        XCTAssertEqual(revoked.revocation, revocation)
        XCTAssertThrowsError(try manager.setEnabled(revoked, true)) { XCTAssertTrue($0.localizedDescription.contains("Sends more than it says.")) }
        XCTAssertEqual(self.manager().extensions.first?.revocation, revocation, "A new manager reads the stored revocation")
        XCTAssertThrowsError(try manager.install(v1, manifest: manifest1, module: moduleV1, from: revoking), "Revoked bytes are not reinstalled")

        var older = catalog([v1], sequence: 3); older.revoked = []
        manager.applyRevocations(from: older)
        XCTAssertNotNil(manager.extensions.first?.revocation, "An older catalog does not lift a revocation")

        try ExtensionCatalogState.record(9, at: manager.catalogStateURL)
        XCTAssertEqual(ExtensionCatalogState.revoked(at: manager.catalogStateURL), [revocation], "Recording a sequence keeps the revocations")

        let (v2, manifest2) = try package(version: "2.0.0", module: moduleV2)
        var fixed = catalog([v2], sequence: 5); fixed.revoked = [revocation]
        manager.applyRevocations(from: fixed)
        let updated = try manager.install(v2, manifest: manifest2, module: moduleV2, from: fixed)
        XCTAssertNil(updated.revocation, "Updating past revoked code clears the warning")
        XCTAssertFalse(updated.enabled, "The revoked version was off, so the update stays off")
        XCTAssertNoThrow(try manager.setEnabled(updated, true))
    }

    func testFailedUpdateRestoresThePreviousVersion() throws {
        let (v1, manifest1) = try package(module: moduleV1)
        let manager = manager()
        try manager.install(v1, manifest: manifest1, module: moduleV1, from: catalog([v1]))
        try manager.setEnabled(try XCTUnwrap(manager.extensions.first), true)
        let (v2, manifest2) = try package(version: "2.0.0", module: moduleV2)
        var moves = 0
        XCTAssertThrowsError(try manager.install(v2, manifest: manifest2, module: moduleV2, from: catalog([v2])) { from, to in
            moves += 1
            if moves == 2 { throw CocoaError(.fileWriteNoPermission) }
            try FileManager.default.moveItem(at: from, to: to)
        }) { XCTAssertTrue(($0 as? ExtensionCatalogError)?.errorDescription?.hasPrefix("Couldn’t install Fictional Reader") == true) }
        let restored = try XCTUnwrap(manager.extensions.first)
        XCTAssertEqual(restored.manifest.version, "1.0.0")
        XCTAssertTrue(restored.enabled)
        XCTAssertEqual(try hidden(), [])
    }

    func testTamperedBytesUnrelatedFoldersAndBundledIDsAreNotReplaced() throws {
        let (listing, manifest) = try package(module: moduleV1)
        let manager = manager()
        var tampered = moduleV1; tampered[13] = 2
        XCTAssertThrowsError(try manager.install(listing, manifest: manifest, module: tampered, from: catalog([listing])))
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: directory.path), [])

        let squatter = directory.appendingPathComponent(listing.id)
        try FileManager.default.createDirectory(at: squatter, withIntermediateDirectories: true)
        try Data("keep".utf8).write(to: squatter.appendingPathComponent("notes.txt"))
        XCTAssertThrowsError(try manager.install(listing, manifest: manifest, module: moduleV1, from: catalog([listing]))) {
            if case .conflict = $0 as? ExtensionCatalogError {} else { XCTFail("Expected a conflict, got \($0)") }
        }
        XCTAssertEqual(try String(contentsOf: squatter.appendingPathComponent("notes.txt"), encoding: .utf8), "keep")

        let bundled = try XCTUnwrap(manager.extensions.first(where: { !$0.isCommunity }), "the test host ships the bundled Hello World extension")
        let (impostor, impostorManifest) = try package(id: bundled.id, module: moduleV1)
        XCTAssertEqual(ExtensionManager.catalogStatus(impostor, installed: manager.extensions), .bundled)
        XCTAssertThrowsError(try manager.install(impostor, manifest: impostorManifest, module: moduleV1, from: catalog([impostor])))
        XCTAssertTrue(ExtensionManager.isBundled(try XCTUnwrap(manager.extensions.first { $0.id == bundled.id }).directory))
    }

    private let squareIcon = Data(base64Encoded: "UklGRh4AAABXRUJQVlA4TBEAAAAvH8AHAAdQvKIUuf+BiOh/AAA=")!
    private let wideIcon = Data(base64Encoded: "UklGRh4AAABXRUJQVlA4TBEAAAAvH8ADAAdQqCIXpf+BiOh/AAA=")!

    func testIconLoadsOnlyWhenItMatchesItsHashFolderAndShape() throws {
        let folder = directory.appendingPathComponent("icons", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = folder.appendingPathComponent("reader.webp")
        try squareIcon.write(to: url)
        XCTAssertEqual(ExtensionIcon.load(url, in: folder, sha256: Integrity.sha256(squareIcon))?.size, NSSize(width: 32, height: 32))
        XCTAssertNil(ExtensionIcon.load(url, in: folder, sha256: Integrity.sha256(wideIcon)), "Hash must match")
        try wideIcon.write(to: url)
        XCTAssertNil(ExtensionIcon.load(url, in: folder, sha256: Integrity.sha256(wideIcon)), "Icons must be square")
        let png = Data([0x89, 0x50, 0x4e, 0x47, 13, 10, 26, 10, 0, 0, 0, 13])
        try png.write(to: url)
        XCTAssertNil(ExtensionIcon.load(url, in: folder, sha256: Integrity.sha256(png)), "Icons must be WebP")
        let outside = root.appendingPathComponent("outside.webp")
        try squareIcon.write(to: outside)
        try FileManager.default.removeItem(at: url)
        try FileManager.default.createSymbolicLink(at: url, withDestinationURL: outside)
        XCTAssertNil(ExtensionIcon.load(url, in: folder, sha256: Integrity.sha256(squareIcon)), "Icons must stay in their folder")
        let large = squareIcon + Data(count: ExtensionManifest.maximumIconBytes)
        try FileManager.default.removeItem(at: url)
        try large.write(to: url)
        XCTAssertNil(ExtensionIcon.load(url, in: folder, sha256: Integrity.sha256(large)), "Icons are capped at 32 KB")
    }

    func testCatalogInstallWritesTheIconAndAMissingIconOffersUpdate() throws {
        let manifest = ExtensionManifest(id: "community.fictional.reader", name: "Fictional Reader", version: "1.0.0", module: "reader.wasm",
                                         capabilities: [], timeoutSeconds: 2, sha256: Integrity.sha256(moduleV1), hosts: ["news.example.com"],
                                         output: "items", icon: "reader.webp", iconSha256: Integrity.sha256(squareIcon))
        let encoder = JSONEncoder(); encoder.outputFormatting = .sortedKeys
        let data = try encoder.encode(manifest)
        var (listing, _) = try package(module: moduleV1)
        listing.manifest = .init(sha256: Integrity.sha256(data), size: data.count)
        listing.icon = "reader.webp"; listing.iconFile = .init(sha256: Integrity.sha256(squareIcon), size: squareIcon.count)
        let manager = manager()
        XCTAssertThrowsError(try manager.install(listing, manifest: data, module: moduleV1, from: catalog([listing])), "A listed icon is required")
        let installed = try manager.install(listing, manifest: data, module: moduleV1, icon: squareIcon, from: catalog([listing]))
        XCTAssertNotNil(ExtensionIcon.image(for: installed))
        XCTAssertEqual(ExtensionManager.catalogStatus(listing, installed: manager.extensions), .installed)
        try FileManager.default.removeItem(at: installed.directory.appendingPathComponent("reader.webp"))
        XCTAssertEqual(ExtensionManager.catalogStatus(listing, installed: manager.extensions), .update(from: "1.0.0"))
    }
}

private extension Result {
    var failureValue: Failure? { if case .failure(let error) = self { return error }; return nil }
}
