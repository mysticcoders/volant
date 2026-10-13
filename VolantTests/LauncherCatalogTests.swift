import AppKit
import CryptoKit
import VolantCore
import XCTest
@testable import Volant

/// The launcher's Extension Catalog: typing `catalog` never fetches, choosing the command or Check
/// Catalog loads it once, typing filters the loaded list, and Return installs without enabling. All
/// files come from memory with a throwaway signing key; the Extensions folder and config are temporary.
@MainActor
final class LauncherCatalogTests: XCTestCase {
    private let module = Data([0, 97, 115, 109, 1, 0, 0, 0, 5, 4, 1, 1, 1, 1])
    private var root: URL!
    private var config: URL { root.appendingPathComponent("config.json") }

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("launcher-catalog-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root.appendingPathComponent("Extensions"), withIntermediateDirectories: true)
        try Data(#"{"extensions":{},"communityExtensionsAllowed":true}"#.utf8).write(to: config)
    }

    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: root) }

    /// A signed in-memory catalog with two fictional readers, and a client that counts fetches.
    private func client(fetches: @escaping (String) -> Void) throws -> ExtensionCatalogClient {
        let key = Curve25519.Signing.PrivateKey()
        var files: [String: Data] = [:]
        var listings: [ExtensionCatalog.Listing] = []
        for (id, name) in [("community.fictional.reader", "Fictional Reader"), ("community.fictional.weather", "Fictional Weather")] {
            let manifest = ExtensionManifest(id: id, name: name, version: "1.0.0", module: "reader.wasm", capabilities: [],
                                             timeoutSeconds: 2, sha256: Integrity.sha256(module), hosts: ["news.example.com"], output: "items")
            let encoder = JSONEncoder(); encoder.outputFormatting = .sortedKeys
            let data = try encoder.encode(manifest)
            let listing = ExtensionCatalog.Listing(id: id, name: name, version: "1.0.0", module: "reader.wasm", summary: "Fictional \(name).",
                                                   publisher: "Fictional Publisher", license: "MIT", hosts: ["news.example.com"],
                                                   source: "https://example.com/\(id)", manifest: .init(sha256: Integrity.sha256(data), size: data.count),
                                                   moduleFile: .init(sha256: Integrity.sha256(module), size: module.count))
            files[listing.manifestPath] = data
            files[listing.modulePath] = module
            listings.append(listing)
        }
        let index = try JSONEncoder().encode(ExtensionCatalog(format: 1, sequence: 1, generated: "2026-10-13T00:00:00Z",
                                                              revision: String(repeating: "d", count: 40), extensions: listings))
        files[ExtensionCatalog.indexPath] = index
        files[ExtensionCatalog.signaturePath] = Data(try key.signature(for: index).base64EncodedString().utf8)
        return ExtensionCatalogClient(fetchFile: { path, _, completion in
            fetches(path)
            completion(files[path].map { .success($0) } ?? .failure(ExtensionCatalogError.unavailable("Missing \(path).")))
        }, publicKey: key.publicKey.rawRepresentation.base64EncodedString(), stateURL: root.appendingPathComponent("extension-catalog.json"))
    }

    private func model(_ actions: @escaping (LauncherAction) -> Void = { _ in }) -> LauncherModel {
        let model = LauncherModel(index: AppIndex(entries: []),
            clipboard: ClipboardStore(retention: 10, storageURL: root.appendingPathComponent("clips.sqlite"), encryptionKey: SymmetricKey(size: .bits256)),
            notes: NotesStore(directory: root.appendingPathComponent("Notes")), config: Preferences(),
            usage: UsageStore(url: root.appendingPathComponent("usage.sqlite")), files: FileSearch(startQuery: { _ in false }), onNote: actions)
        model.searchesSecondarySources = false
        model.appleShortcuts.loadOverride = { $0([], nil) }
        model.actionConfigURL = config
        model.extensions = ExtensionManager(configURL: config, directory: root.appendingPathComponent("Extensions"))
        model.dismiss = {}
        return model
    }

    private func settle() async { for _ in 0..<5 { await Task.yield(); try? await Task.sleep(nanoseconds: 20_000_000) } }

    func testTypingCatalogNeverFetchesAndCheckLoadsOnce() async throws {
        var fetched: [String] = []
        let model = model()
        model.catalogClient = try client { fetched.append($0) }
        model.query = "catalog"
        XCTAssertEqual(model.rows.map(\.id), ["catalog:check"])
        model.query = "catalog fictional"
        XCTAssertEqual(fetched, [], "Typing a catalog query must not contact the catalog")
        XCTAssertTrue(LauncherRouting.isReserved("catalog fictional"))
        model.query = "catalog"
        model.activateSelection()
        await settle()
        XCTAssertEqual(fetched, [ExtensionCatalog.indexPath, ExtensionCatalog.signaturePath])
        XCTAssertEqual(model.rows.map(\.id), ["catalog:community.fictional.reader", "catalog:community.fictional.weather"])
        model.query = "catalog weather"
        XCTAssertEqual(model.rows.map(\.id), ["catalog:community.fictional.weather"])
        model.query = "catalog nothing like this"
        XCTAssertTrue(model.rows.isEmpty)
        XCTAssertEqual(fetched.count, 2, "Filtering reuses the loaded catalog")
    }

    func testChoosingTheCommandLoadsTheCatalog() async throws {
        var fetched: [String] = []
        let model = model()
        model.catalogClient = try client { fetched.append($0) }
        XCTAssertTrue(CoreCommand.search("store").contains(.catalog))
        model.query = "extension catalog"
        let index = try XCTUnwrap(model.rows.firstIndex { $0.id == "core:catalog" })
        XCTAssertEqual(fetched, [])
        model.selection = index
        model.activateSelection()
        await settle()
        XCTAssertEqual(model.query, "catalog ")
        XCTAssertEqual(model.rows.count, 2)
    }

    func testReturnInstallsWithoutEnablingAndThenUsesTheExtension() async throws {
        let model = model()
        model.catalogClient = try client { _ in }
        model.query = "catalog"
        model.activateSelection()
        await settle()
        model.query = "catalog reader"
        XCTAssertEqual(model.selectedRow?.primaryAction, "Install Extension")
        XCTAssertEqual(model.selectedRow?.secondaryAction, "View Source")
        model.activateSelection()
        await settle()
        let installed = try XCTUnwrap(model.extensions.extensions.first { $0.id == "community.fictional.reader" })
        XCTAssertFalse(installed.enabled)
        XCTAssertTrue(ExtensionHostApprovals.approved(at: config).isEmpty)
        XCTAssertEqual(model.selectedRow?.primaryAction, "Use Extension")
        model.activateSelection()
        XCTAssertEqual(model.query, "Fictional Reader ")
    }

    func testCommunityOffOpensSettingsInsteadOfInstalling() async throws {
        try Data(#"{"extensions":{}}"#.utf8).write(to: config)
        var actions: [String] = []
        let model = model { actions.append(String(describing: $0)) }
        model.catalogClient = try client { _ in }
        model.query = "catalog"
        model.activateSelection()
        await settle()
        model.query = "catalog reader"
        model.activateSelection()
        await settle()
        XCTAssertEqual(actions, ["extensionSettings"])
        XCTAssertFalse(model.extensions.extensions.contains { $0.isCommunity })
    }
}
