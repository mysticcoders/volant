import XCTest
import VolantCore
@testable import Volant

/// Storing and sending an extension's declared preferences, with a scripted module in place of the
/// extension helper. Every file is temporary and fictional.
@MainActor
final class ExtensionPreferenceRunTests: XCTestCase {
    private var root: URL!
    private var config: URL { root.appendingPathComponent("config.json") }
    private var folder: URL { root.appendingPathComponent("reader", isDirectory: true) }
    private let declared = [
        ExtensionPreference(id: "hideDomains", type: .text, title: "Hidden domains", maxLength: 100),
        ExtensionPreference(id: "limit", type: .number, title: "Rows", defaultValue: .number(30), min: 5, max: 50),
    ]

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("preferences-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try Data(#"{"extensions":{},"communityExtensionsAllowed":true,"fictionalUnknownField":{"kept":true}}"#.utf8).write(to: config)
    }

    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: root) }

    private func writeManifest(_ preferences: [ExtensionPreference]?) throws {
        let module = Data([0, 97, 115, 109, 1, 0, 0, 0, 5, 4, 1, 1, 1, 1])
        try module.write(to: folder.appendingPathComponent("reader.wasm"))
        let manifest = ExtensionManifest(id: "community.fictional.reader", name: "Fictional Reader", version: "1", module: "reader.wasm",
                                         capabilities: [], timeoutSeconds: 2, sha256: Integrity.sha256(module), output: "items",
                                         preferences: preferences)
        try JSONEncoder().encode(manifest).write(to: folder.appendingPathComponent("manifest.json"))
    }

    private func manager() throws -> (ExtensionManager, InstalledExtension) {
        try writeManifest(declared)
        let manager = ExtensionManager(configURL: config, roots: [folder], dataDirectory: root.appendingPathComponent("ExtensionData"))
        manager.reload()
        try manager.setEnabled(try XCTUnwrap(manager.extensions.first), true)
        return (manager, try XCTUnwrap(manager.extensions.first))
    }

    private func request(_ manager: ExtensionManager, _ ext: InstalledExtension) -> String {
        var requests: [String] = []
        manager.invokeOverride = { _, input, completion in requests.append(input); completion(.success(#"{"items":[]}"#)) }
        manager.runItems(ext, query: "", fetch: { _, _, _ in XCTFail("No hosts, no fetch") }) { _ in }
        return requests.first ?? ""
    }

    func testDefaultsThenSavedChoicesReachTheExtension() throws {
        let (manager, ext) = try manager()
        XCTAssertTrue(request(manager, ext).contains(#""preferences":{"hideDomains":"","limit":30}"#))
        try manager.savePreferences(["hideDomains": .string("fictional.example"), "limit": .number(12)], for: ext, expected: [:])
        XCTAssertTrue(request(manager, ext).contains(#""preferences":{"hideDomains":"fictional.example","limit":12}"#))
    }

    func testSavingKeepsOtherConfigAndStoresOnlyNonDefaultDeclaredValues() throws {
        let (manager, ext) = try manager()
        try manager.savePreferences(["hideDomains": .string(""), "limit": .number(12), "undeclared": .bool(true)], for: ext, expected: [:])
        XCTAssertEqual(ExtensionPreferenceStore.values(for: ext.id, at: config), ["limit": .number(12)])
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: config)) as? [String: Any])
        XCTAssertEqual((object["fictionalUnknownField"] as? [String: Any])?["kept"] as? Bool, true, "Unrelated config fields survive")
        XCTAssertTrue(ExtensionApproval.enabled(ext.manifest, at: config), "Saving preferences never touches approval")
    }

    func testAStaleEditorIsRefused() throws {
        let (manager, ext) = try manager()
        try manager.savePreferences(["limit": .number(12)], for: ext, expected: [:])
        XCTAssertThrowsError(try manager.savePreferences(["limit": .number(40)], for: ext, expected: [:]), "Opened before the first save")
        XCTAssertEqual(ExtensionPreferenceStore.values(for: ext.id, at: config), ["limit": .number(12)])
    }

    func testChangingDeclaredPreferencesKeepsTheExtensionEnabled() throws {
        let (manager, ext) = try manager()
        try writeManifest([ExtensionPreference(id: "sort", type: .toggle, title: "Newest first")])
        manager.reload()
        let changed = try XCTUnwrap(manager.extensions.first)
        XCTAssertNotEqual(changed.manifest, ext.manifest)
        XCTAssertTrue(changed.enabled, "Preferences are not part of the approval fingerprint")
    }

    func testUninstallForgetsPreferences() throws {
        let (manager, ext) = try manager()
        try manager.savePreferences(["limit": .number(12)], for: ext, expected: [:])
        try manager.uninstall(ext, remove: { try FileManager.default.removeItem(at: $0) })
        XCTAssertTrue(ExtensionPreferenceStore.values(for: ext.id, at: config).isEmpty)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: config)) as? [String: Any])
        XCTAssertNil(object[ExtensionPreferenceStore.key], "No empty preferences object is left behind")
    }
}
