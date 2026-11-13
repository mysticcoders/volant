import CryptoKit
import SwiftUI
import VolantCore
import XCTest
@testable import Volant

/// Row image previews in the launcher: rows keep their `image`, previews load through the extension
/// manager only when a row asks, a new list or leaving the extension drops results still loading, and
/// the row view shows the placeholder until an image arrives. A scripted module and a fake fetch helper
/// stand in for the extension and fetch helpers; every file is temporary and fictional.
@MainActor
final class LauncherExtensionImageTests: XCTestCase {
    private var root: URL!
    private var config: URL { root.appendingPathComponent("config.json") }
    private var folder: URL { root.appendingPathComponent("favicons", isDirectory: true) }
    private var pending: [(ExtensionRequest, (ExtensionFetcher.RowImageReply) -> Void)] = []

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("launcher-images-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try Data(#"{"extensions":{},"communityExtensionsAllowed":true}"#.utf8).write(to: config)
        pending = []
    }

    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: root) }

    /// A launcher inside Fictional Favicons, which declares `row-images` on `icons.example.com` and lists `rows`.
    private func model(rows: String) async throws -> LauncherModel {
        let module = Data([0, 97, 115, 109, 1, 0, 0, 0, 5, 4, 1, 1, 1, 1])
        try module.write(to: folder.appendingPathComponent("favicons.wasm"))
        let manifest = ExtensionManifest(id: "community.fictional.favicons", name: "Fictional Favicons", version: "1", module: "favicons.wasm",
                                         capabilities: [], timeoutSeconds: 2, sha256: Integrity.sha256(module), hosts: ["icons.example.com"],
                                         output: "items", permissions: ["row-images"])
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
        model.extensions.fetchRowImage = { [unowned self] request, _, completion in pending.append((request, completion)) }
        model.extensions.fetchCopy = { _, _, _ in XCTFail("Showing rows never copies") }
        model.extensions.invokeOverride = { _, _, completion in completion(.success(#"{"items":\#(rows)}"#)) }
        model.query = "Fictional Favicons"
        let row = try XCTUnwrap(model.rows.first { if case .extensionRun = $0 { return true }; return false })
        model.activate(rowID: row.id)
        let end = Date().addingTimeInterval(1)
        while !model.rows.contains(where: { if case .extensionItem = $0 { return true }; return false }), Date() < end { try await Task.sleep(nanoseconds: 20_000_000) }
        return model
    }

    private let rows = #"[{"title":"Fictional site","url":"https://site.example.com","image":{"url":"https://icons.example.com/site.ico"}},{"title":"Plain site","url":"https://plain.example.com"}]"#

    private func items(_ model: LauncherModel) -> [(ExtensionItem, InstalledExtension)] {
        model.rows.compactMap { if case .extensionItem(let item, let ext) = $0 { return (item, ext) }; return nil }
    }

    func testRowsKeepTheirImageAndNothingLoadsUntilARowAsks() async throws {
        let model = try await model(rows: rows)
        let listed = items(model)
        XCTAssertEqual(listed.map(\.0.image?.url), ["https://icons.example.com/site.ico", nil])
        XCTAssertTrue(pending.isEmpty, "Listing loads no images")
        let (item, ext) = listed[0]
        model.rowState.extensionImages.request(try XCTUnwrap(item.image?.url), for: ext)
        XCTAssertEqual(pending.map(\.0.url.absoluteString), ["https://icons.example.com/site.ico"])
        pending[0].1(.thumbnail(try XCTUnwrap(ExtensionImageFixtures.image(.png, width: 32, height: 32))))
        XCTAssertNotNil(model.rowState.extensionImages.image("https://icons.example.com/site.ico", for: ext))
    }

    func testLeavingTheExtensionDropsImagesStillLoading() async throws {
        let model = try await model(rows: rows)
        let (item, ext) = items(model)[0]
        model.rowState.extensionImages.request(try XCTUnwrap(item.image?.url), for: ext)
        model.exitScope()
        pending[0].1(.thumbnail(try XCTUnwrap(ExtensionImageFixtures.image(.png))))
        XCTAssertNil(model.rowState.extensionImages.image("https://icons.example.com/site.ico", for: ext))
        XCTAssertEqual(model.rowState.extensionImages.cachedCount, 0)
    }

    func testTheRowViewShowsThePlaceholderUntilTheImageLoads() throws {
        let images = ExtensionRowImages()
        let manifest = ExtensionManifest(id: "community.fictional.favicons", name: "Fictional Favicons", version: "1", module: "favicons.wasm",
                                         capabilities: [], sha256: String(repeating: "a", count: 64), hosts: ["icons.example.com"], output: "items",
                                         permissions: ["row-images"])
        let ext = InstalledExtension(id: manifest.id, manifest: manifest, directory: root)
        var requested: [String] = []
        var finish: ((ExtensionManager.RowImageOutcome) -> Void)?
        images.load = { _, url, done in requested.append(url); finish = done }
        images.authorize = { _, _ in true }
        let view = ExtensionRowImage(url: "https://icons.example.com/site.ico", source: ext, images: images) { Color(red: 0, green: 1, blue: 0) }
        let host = NSHostingView(rootView: view.frame(width: 24, height: 24))
        host.frame = NSRect(x: 0, y: 0, width: 24, height: 24)
        func center() -> ExtensionImageFixtures.Color? {
            host.layoutSubtreeIfNeeded()
            RunLoop.main.run(until: Date().addingTimeInterval(0.05))
            guard let bitmap = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { return nil }
            host.cacheDisplay(in: host.bounds, to: bitmap)
            guard let color = bitmap.colorAt(x: 12, y: 12)?.usingColorSpace(.sRGB) else { return nil }
            return ExtensionImageFixtures.Color(red: UInt8(color.redComponent * 255), green: UInt8(color.greenComponent * 255), blue: UInt8(color.blueComponent * 255))
        }
        let placeholder = try XCTUnwrap(center())
        XCTAssertTrue(ExtensionImageFixtures.close(placeholder, ExtensionImageFixtures.Color(red: 0, green: 255, blue: 0), tolerance: 40), "Placeholder while loading: \(placeholder)")
        XCTAssertEqual(requested, ["https://icons.example.com/site.ico"], "The row asks for its image when it appears")
        let thumbnail = try XCTUnwrap(ExtensionRowImages.thumbnail(try XCTUnwrap(ExtensionImageFixtures.image(.png, width: 48, height: 48, ExtensionImageFixtures.red))))
        try XCTUnwrap(finish)(.image(thumbnail))
        let loaded = try XCTUnwrap(center())
        XCTAssertTrue(ExtensionImageFixtures.close(loaded, ExtensionImageFixtures.red, tolerance: 40), "The loaded image replaces the placeholder: \(loaded)")
        images.reset()
        let again = try XCTUnwrap(center())
        XCTAssertTrue(ExtensionImageFixtures.close(again, ExtensionImageFixtures.red, tolerance: 40),
                      "A row that stays on screen in a new list shows its cached image again: \(again)")
        XCTAssertEqual(requested.count, 1, "From the cache, without fetching again")
    }
}
