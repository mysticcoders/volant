import CryptoKit
import VolantCore
import XCTest
@testable import Volant

/// A list extension row's copy in the launcher: where the Actions menu lists it, what Return does, and
/// the confirmation or failure shown afterward. A scripted module and a fake clipboard stand in for the
/// extension helper and the owner's pasteboard; every file is temporary and fictional.
@MainActor
final class LauncherExtensionCopyTests: XCTestCase {
    private var root: URL!
    private var config: URL { root.appendingPathComponent("config.json") }
    private var folder: URL { root.appendingPathComponent("logos", isDirectory: true) }
    private var written: [ExtensionCopyContent] = []

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("launcher-copy-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try Data(#"{"extensions":{},"communityExtensionsAllowed":true}"#.utf8).write(to: config)
        written = []
    }

    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: root) }

    /// A launcher inside Fictional Logos, which declares `clipboard-write` and lists `rows`.
    private func model(rows: String) async throws -> LauncherModel {
        let module = Data([0, 97, 115, 109, 1, 0, 0, 0, 5, 4, 1, 1, 1, 1])
        try module.write(to: folder.appendingPathComponent("logos.wasm"))
        let manifest = ExtensionManifest(id: "community.fictional.logos", name: "Fictional Logos", version: "1", module: "logos.wasm",
                                         capabilities: [], timeoutSeconds: 2, sha256: Integrity.sha256(module), output: "items",
                                         permissions: ["clipboard-write"])
        try JSONEncoder().encode(manifest).write(to: folder.appendingPathComponent("manifest.json"))
        let model = LauncherModel(index: AppIndex(entries: []),
            clipboard: ClipboardStore(retention: 10, storageURL: root.appendingPathComponent("clips.sqlite"), encryptionKey: SymmetricKey(size: .bits256)),
            notes: NotesStore(directory: root.appendingPathComponent("Notes")), config: Preferences(),
            usage: UsageStore(url: root.appendingPathComponent("usage.sqlite")), files: FileSearch(home: .unavailable)) { _ in }
        model.searchesSecondarySources = false
        model.appleShortcuts.loadOverride = { $0([], nil) }
        model.actionConfigURL = config
        model.extensions = ExtensionManager(configURL: config, roots: [folder], dataDirectory: root.appendingPathComponent("ExtensionData"))
        model.extensions.reload()
        try model.extensions.setEnabled(try XCTUnwrap(model.extensions.extensions.first), true)
        model.extensions.writeClipboard = { [unowned self] in written.append($0) }
        model.extensions.fetchCopy = { _, _, _ in XCTFail("These rows copy text only") }
        model.extensions.invokeOverride = { _, _, completion in completion(.success(#"{"items":\#(rows)}"#)) }
        model.copyText = { _ in XCTFail("A row's copy goes through the extension manager") }
        model.dismiss = { XCTFail("Copying keeps the launcher open") }
        model.query = "Fictional Logos"
        let row = try XCTUnwrap(model.rows.first { if case .extensionRun = $0 { return true }; return false })
        model.activate(rowID: row.id)
        let end = Date().addingTimeInterval(1)
        while !model.rows.contains(where: { if case .extensionItem = $0 { return true }; return false }), Date() < end { try await Task.sleep(nanoseconds: 20_000_000) }
        return model
    }

    func testTheCopyEntryFollowsTheLinksAndReturnStillOpensALink() async throws {
        let model = try await model(rows: #"[{"title":"Fictional logo","url":"https://example.com/logo","secondaryURL":"https://example.com/brand","copy":{"text":"<svg/>","title":"Copy SVG"},"actions":[{"id":"pin","title":"Pin Logo"}]}]"#)
        let row = try XCTUnwrap(model.selectedRow)
        XCTAssertEqual(row.menuEntries, [.item(.open), .item(.reveal), .item(.copyPath), .copy("Copy SVG"), .custom(ExtensionItemAction(id: "pin", title: "Pin Logo"))])
        XCTAssertEqual(row.primaryAction, "Open Link", "A row with a link keeps opening it on Return")
        XCTAssertTrue(row.supportsActions)
        model.performMenuEntry(.copy("Copy SVG"), target: row)
        XCTAssertEqual(written, [.text("<svg/>")])
        XCTAssertEqual(model.actionFeedback, "Copied SVG")
        XCTAssertNil(model.actionTarget)
    }

    func testReturnCopiesWhenTheRowHasNoLink() async throws {
        let model = try await model(rows: #"[{"title":"Fictional wordmark","copy":{"text":"<svg/>","title":"Copy SVG"}}]"#)
        let row = try XCTUnwrap(model.selectedRow)
        XCTAssertEqual(row.primaryAction, "Copy SVG")
        XCTAssertEqual(row.menuEntries, [.item(.open)], "Return's own entry is the copy, so it is not listed twice")
        XCTAssertTrue(row.supportsActions)
        model.activateSelection()
        XCTAssertEqual(written, [.text("<svg/>")])
        XCTAssertEqual(model.actionFeedback, "Copied SVG")
        model.performMenuEntry(.item(.open), target: row)
        XCTAssertEqual(written.count, 2, "Open in the Actions menu is Return, which copies")
    }

    func testARowWhoseReturnRunsAnActionListsItsCopy() async throws {
        let model = try await model(rows: #"[{"title":"Fictional icon","primaryAction":"pin","actions":[{"id":"pin","title":"Pin"}],"copy":{"text":"icon"}}]"#)
        let row = try XCTUnwrap(model.selectedRow)
        XCTAssertEqual(row.menuEntries, [.item(.open), .copy("Copy"), .custom(ExtensionItemAction(id: "pin", title: "Pin"))])
    }

    func testAFailedCopyExplainsAndCopiesNothing() async throws {
        let model = try await model(rows: #"[{"title":"Fictional wordmark","copy":{"text":"<svg/>"}}]"#)
        let ext = try XCTUnwrap(model.extensions.extensions.first)
        try model.extensions.setEnabled(ext, false)
        model.activateSelection()
        XCTAssertTrue(written.isEmpty)
        XCTAssertEqual(model.actionFeedback, "Fictional Logos: " + (ExtensionManager.ExtensionError.disabled.errorDescription ?? ""))
    }

    func testRowsWithoutTheCopyKeepCopyingTheirTitle() async throws {
        let model = try await model(rows: #"[{"title":"Fictional plain row"}]"#)
        let row = try XCTUnwrap(model.selectedRow)
        XCTAssertEqual(row.primaryAction, "Copy Title")
        XCTAssertEqual(row.menuEntries, [.item(.open)])
        XCTAssertFalse(row.supportsActions)
    }
}
