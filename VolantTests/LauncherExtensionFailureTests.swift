import CryptoKit
import VolantCore
import XCTest
@testable import Volant

/// A command extension's failure must be visible: the launcher shows a notice only when it has no
/// rows, so a failed run replaces the rows instead of leaving the chosen row in place. Every file is
/// temporary and fictional.
@MainActor
final class LauncherExtensionFailureTests: XCTestCase {
    private var root: URL!
    private var config: URL { root.appendingPathComponent("config.json") }
    private var folder: URL { root.appendingPathComponent("command", isDirectory: true) }

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("extension-failure-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try Data(#"{"extensions":{},"communityExtensionsAllowed":true}"#.utf8).write(to: config)
    }

    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: root) }

    /// Chooses an enabled command extension whose approval was withdrawn on disk after the launcher
    /// loaded it, so the run fails before reaching the helper.
    func testFailedRunShowsItsNoticeInPlaceOfTheRows() throws {
        let module = Data([0, 97, 115, 109, 1, 0, 0, 0, 5, 4, 1, 1, 1, 1])
        try module.write(to: folder.appendingPathComponent("command.wasm"))
        let manifest = ExtensionManifest(id: "community.fictional.command", name: "Fictional Command", version: "1", module: "command.wasm",
                                         capabilities: [], timeoutSeconds: 2, sha256: Integrity.sha256(module))
        try JSONEncoder().encode(manifest).write(to: folder.appendingPathComponent("manifest.json"))
        let model = LauncherModel(index: AppIndex(entries: []),
            clipboard: ClipboardStore(retention: 10, storageURL: root.appendingPathComponent("clips.sqlite"), encryptionKey: SymmetricKey(size: .bits256)),
            notes: NotesStore(directory: root.appendingPathComponent("Notes")), config: Preferences(),
            usage: UsageStore(url: root.appendingPathComponent("usage.sqlite")), files: FileSearch(startQuery: { _ in false })) { _ in }
        model.searchesSecondarySources = false
        model.appleShortcuts.loadOverride = { $0([], nil) }
        model.actionConfigURL = config
        model.extensions = ExtensionManager(configURL: config, roots: [folder], dataDirectory: root.appendingPathComponent("ExtensionData"))
        model.extensions.reload()
        try model.extensions.setEnabled(try XCTUnwrap(model.extensions.extensions.first), true)
        model.dismiss = {}
        model.query = "Fictional Command"
        let row = try XCTUnwrap(model.rows.first { if case .extensionRun = $0 { return true }; return false })
        try Data(#"{"extensions":{},"communityExtensionsAllowed":true}"#.utf8).write(to: config)
        model.activate(rowID: row.id)
        XCTAssertTrue(model.sections.isEmpty, "The chosen row no longer hides the notice")
        XCTAssertEqual(model.notice, "Extension failed: Extension is disabled. Enable it before running.")
    }
}
