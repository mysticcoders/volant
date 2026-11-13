import AppKit
import ImageIO
import VolantCore
import XCTest
@testable import Volant

/// Row image previews with the `row-images` permission: when `ExtensionManager.loadRowImage` fetches and
/// what it records, and how `ExtensionRowImages` bounds, caches and drops results. A fake fetch helper
/// stands in for VolantFetchHost; every file and image is temporary and fictional.
@MainActor
final class ExtensionRowImageTests: XCTestCase {
    private var root: URL!
    private var config: URL { root.appendingPathComponent("config.json") }
    private var folder: URL { root.appendingPathComponent("favicons", isDirectory: true) }
    private let host = "icons.example.com"
    private var fetched: [(ExtensionRequest, [String])] = []
    private var reply: ExtensionFetcher.RowImageReply = .stopped
    private var activity = ExtensionActivityRecorder()

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("row-images-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try Data(#"{"extensions":{},"communityExtensionsAllowed":true}"#.utf8).write(to: config)
        fetched = []; activity = ExtensionActivityRecorder()
        reply = .thumbnail(try XCTUnwrap(ExtensionImageFixtures.image(.png)))
    }

    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: root) }

    private func writeManifest(permissions: [String]?) throws {
        let module = Data([0, 97, 115, 109, 1, 0, 0, 0, 5, 4, 1, 1, 1, 1])
        try module.write(to: folder.appendingPathComponent("favicons.wasm"))
        let manifest = ExtensionManifest(id: "community.fictional.favicons", name: "Fictional Favicons", version: "1", module: "favicons.wasm",
                                         capabilities: [], timeoutSeconds: 2, sha256: Integrity.sha256(module), hosts: [host], output: "items",
                                         permissions: permissions)
        try JSONEncoder().encode(manifest).write(to: folder.appendingPathComponent("manifest.json"))
    }

    /// One installed, enabled list extension on `icons.example.com` with a fake fetch helper.
    private func manager(permissions: [String]? = ["row-images"]) throws -> (ExtensionManager, InstalledExtension) {
        try writeManifest(permissions: permissions)
        let manager = ExtensionManager(configURL: config, roots: [folder], dataDirectory: root.appendingPathComponent("ExtensionData"))
        manager.reload()
        try manager.setEnabled(try XCTUnwrap(manager.extensions.first), true)
        manager.activity = activity
        manager.fetchRowImage = { [unowned self] request, hosts, completion in fetched.append((request, hosts)); completion(reply) }
        return (manager, try XCTUnwrap(manager.extensions.first))
    }

    private func load(_ manager: ExtensionManager, _ ext: InstalledExtension, _ url: String = "https://icons.example.com/site.ico") -> ExtensionManager.RowImageOutcome? {
        var outcome: ExtensionManager.RowImageOutcome?
        manager.loadRowImage(ext, url: url) { outcome = $0 }
        return outcome
    }

    private func isImage(_ outcome: ExtensionManager.RowImageOutcome?) -> Bool { if case .image? = outcome { return true }; return false }
    private func name(_ outcome: ExtensionManager.RowImageOutcome?) -> String {
        switch outcome {
        case .image?: "image"
        case .failed?: "failed"
        case .refused?: "refused"
        case .stopped?: "stopped"
        case nil: "none"
        }
    }

    private var fetchEvents: [ExtensionActivity] { activity.log.events.filter { $0.operation == .fetch } }

    // MARK: Loading

    func testAnApprovedImageLoadsThroughTheHelperAndRecordsOnlyTheHost() throws {
        let (manager, ext) = try manager()
        XCTAssertTrue(isImage(load(manager, ext, "https://icons.example.com/ip3/site.example.com.ico?size=64")))
        XCTAssertEqual(fetched.first?.0.url.absoluteString, "https://icons.example.com/ip3/site.example.com.ico?size=64")
        XCTAssertEqual(fetched.first?.0.method, "GET")
        XCTAssertEqual(fetched.first?.1, [host], "The helper gets only approved declared hosts")
        XCTAssertEqual(fetchEvents.map(\.outcome), [.completed])
        XCTAssertEqual(fetchEvents.map(\.detail), [host], "Activity names the host, never the path or query")
    }

    func testFailuresAndInvalidThumbnailsShowNothing() throws {
        let (manager, ext) = try manager()
        reply = .failed(status: 404)
        XCTAssertEqual(name(load(manager, ext)), "failed")
        reply = .thumbnail(try XCTUnwrap(ExtensionImageFixtures.image(.jpeg)))
        XCTAssertEqual(name(load(manager, ext)), "failed", "Only PNG thumbnails are decoded in the app")
        reply = .thumbnail(try XCTUnwrap(ExtensionImageFixtures.image(.png, width: 128, height: 128)))
        XCTAssertEqual(name(load(manager, ext)), "failed", "A thumbnail larger than 64 pixels is refused")
        reply = .stopped
        XCTAssertEqual(name(load(manager, ext)), "stopped")
        XCTAssertEqual(fetchEvents.map(\.outcome), [.failed, .failed, .failed, .cancelled])
    }

    func testImagesNeedThePermissionAnApprovedDeclaredHostAndAnAllowedExtension() throws {
        let (plain, plainExt) = try manager(permissions: nil)
        XCTAssertEqual(name(load(plain, plainExt)), "refused", "Without row-images nothing loads")
        XCTAssertTrue(fetched.isEmpty)

        let (manager, ext) = try manager()
        XCTAssertEqual(name(load(manager, ext, "https://other.example.com/a.png")), "refused", "Undeclared host")
        XCTAssertEqual(name(load(manager, ext, "http://icons.example.com/a.png")), "refused", "Plain http")
        try ExtensionHostApprovals.remove(host, at: config)
        XCTAssertEqual(name(load(manager, ext)), "refused", "A host the owner removed")
        try ExtensionHostApprovals.approve([host], at: config)
        try manager.setCommunityAllowed(false, expected: true)
        XCTAssertEqual(name(load(manager, ext)), "refused", "The community switch is off")
        try manager.setCommunityAllowed(true, expected: false)
        try manager.setEnabled(ext, false)
        XCTAssertEqual(name(load(manager, ext)), "refused", "The extension is off")
        try manager.setEnabled(try XCTUnwrap(manager.extensions.first), true)
        let revoked = ExtensionCatalog.Revocation(id: ext.id, sha256: try XCTUnwrap(ext.manifest.sha256), reason: "Fictional reason.")
        try ExtensionCatalogState.recordRevocations([revoked], sequence: 1, at: manager.catalogStateURL)
        XCTAssertEqual(name(load(manager, ext)), "refused", "The catalog revoked it")
        XCTAssertTrue(fetched.isEmpty, "Nothing refused is ever fetched")
        XCTAssertEqual(Set(fetchEvents.map(\.outcome)), [.denied])
    }

    func testChangesDuringTheFetchDropTheResult() throws {
        let (manager, ext) = try manager()
        let thumbnail = reply
        manager.fetchRowImage = { [unowned self] _, _, completion in
            try? ExtensionHostApprovals.remove(host, at: config)
            completion(thumbnail)
        }
        XCTAssertEqual(name(load(manager, ext)), "refused", "A host removed mid-fetch")
        try ExtensionHostApprovals.approve([host], at: config)
        manager.fetchRowImage = { _, _, completion in
            try? manager.setCommunityAllowed(false, expected: true)
            completion(thumbnail)
        }
        XCTAssertEqual(name(load(manager, ext)), "refused", "The community switch turned off mid-fetch")
    }

    func testRowImagesArePartOfTheApprovalAndShownToTheOwner() throws {
        let (manager, ext) = try manager(permissions: nil)
        let without = try ExtensionApproval.fingerprint(ext.manifest)
        try writeManifest(permissions: ["row-images"])
        manager.reload()
        let added = try XCTUnwrap(manager.extensions.first)
        XCTAssertNotEqual(try ExtensionApproval.fingerprint(added.manifest), without)
        XCTAssertFalse(added.enabled, "Adding row-images needs enabling again")
        XCTAssertFalse(added.manifest.requestsNoMoreThan(ext.manifest), "A catalog update that adds it turns the extension off")
        XCTAssertTrue(added.accessDescription.contains("Show images from its sites in its rows"), added.accessDescription)
        XCTAssertFalse(ext.accessDescription.contains("Show images"))
    }

    func testListRunsKeepImagesOnlyWithThePermissionAndNeverFetchThem() throws {
        let plan = #"{"items":[{"title":"Fictional site","url":"https://site.example.com","image":{"url":"https://icons.example.com/site.ico"}}]}"#
        for (permissions, kept) in [(["row-images"], true), (nil, false)] as [([String]?, Bool)] {
            let (manager, ext) = try manager(permissions: permissions)
            var listed: [ExtensionItem]?
            manager.invokeOverride = { _, _, completion in completion(.success(plan)) }
            manager.runItems(ext, query: "", fetch: { _, _, _ in XCTFail("No fetch") }) { listed = try? $0.get() }
            XCTAssertEqual(listed?.first?.image != nil, kept)
        }
        XCTAssertTrue(fetched.isEmpty, "Listing never loads an image; only rows on screen do")
    }

    // MARK: The launcher's loader

    private struct PendingLoad { let url: String; let done: (ExtensionManager.RowImageOutcome) -> Void }

    /// A loader whose loads wait until the test completes them, with every extension and host allowed
    /// unless `allowed` says otherwise.
    private func loader(allowed: @escaping () -> Bool = { true }) -> (ExtensionRowImages, () -> [PendingLoad], (Int) -> Void) {
        let images = ExtensionRowImages()
        var pending: [PendingLoad] = []
        images.load = { _, url, done in pending.append(PendingLoad(url: url, done: done)) }
        images.authorize = { _, _ in allowed() }
        return (images, { pending }, { index in pending.remove(at: index).done(.image(Self.thumbnailImage)) })
    }

    private static let thumbnailImage = NSImage(cgImage: ExtensionImageFixtures.cgImage(width: 32, height: 32, ExtensionImageFixtures.blue), size: NSSize(width: 32, height: 32))

    private func fixtureExtension() throws -> InstalledExtension { try manager().1 }

    func testFetchesRunFourAtATimeAndThirtyPerList() throws {
        let ext = try fixtureExtension()
        let (images, pending, complete) = loader()
        for index in 0..<40 { images.request("https://icons.example.com/\(index).png", for: ext) }
        XCTAssertEqual(pending().count, ExtensionItemImage.maximumConcurrentFetches)
        XCTAssertEqual(images.inFlight, 4)
        var completed = 0
        while !pending().isEmpty { complete(0); completed += 1 }
        XCTAssertEqual(completed, ExtensionItemImage.maximumFetchesPerList, "Rows past the thirtieth keep the placeholder")
        XCTAssertNotNil(images.image("https://icons.example.com/0.png", for: ext))
        XCTAssertNil(images.image("https://icons.example.com/35.png", for: ext))
        images.reset()
        images.request("https://icons.example.com/35.png", for: ext)
        XCTAssertEqual(pending().count, 1, "A new list may fetch again")
    }

    func testAResultForAStaleListIsDropped() throws {
        let ext = try fixtureExtension()
        let (images, pending, complete) = loader()
        images.request("https://icons.example.com/old.png", for: ext)
        images.reset()
        complete(0)
        XCTAssertNil(images.image("https://icons.example.com/old.png", for: ext), "Not shown in the new list")
        XCTAssertEqual(images.cachedCount, 0, "Not cached either")
        XCTAssertEqual(images.inFlight, 0)
        images.request("https://icons.example.com/old.png", for: ext)
        XCTAssertEqual(pending().count, 1, "The new list fetches it again")
    }

    func testCachedImagesAreShownAgainOnlyWhileAllowed() throws {
        let ext = try fixtureExtension()
        var allowed = true
        let (images, pending, complete) = loader(allowed: { allowed })
        images.request("https://icons.example.com/a.png", for: ext)
        complete(0)
        images.reset()
        images.request("https://icons.example.com/a.png", for: ext)
        XCTAssertTrue(pending().isEmpty, "A cached image is not fetched again")
        XCTAssertNotNil(images.image("https://icons.example.com/a.png", for: ext))
        images.reset()
        allowed = false
        images.request("https://icons.example.com/a.png", for: ext)
        XCTAssertNil(images.image("https://icons.example.com/a.png", for: ext), "Not shown once the extension or host is no longer allowed")
    }

    func testFailuresAreRememberedButRefusalsAndStopsMayRetry() throws {
        let ext = try fixtureExtension()
        let (images, pending, _) = loader()
        images.request("https://icons.example.com/broken.png", for: ext)
        pending()[0].done(.failed)
        images.reset()
        images.request("https://icons.example.com/broken.png", for: ext)
        XCTAssertEqual(pending().count, 1, "Only the first load is pending; the failure is cached for the session")
        images.request("https://icons.example.com/refused.png", for: ext)
        pending()[1].done(.refused)
        images.request("https://icons.example.com/refused.png", for: ext)
        XCTAssertEqual(pending().count, 3, "A refusal may load again when the row reappears")
    }

    func testTheCacheIsBoundedByCountAndBytes() throws {
        let ext = try fixtureExtension()
        let (images, pending, complete) = loader()
        for batch in 0..<10 {
            images.reset()
            for index in 0..<25 { images.request("https://icons.example.com/\(batch)-\(index).png", for: ext) }
            while !pending().isEmpty { complete(0) }
        }
        XCTAssertEqual(images.cachedCount, ExtensionItemImage.maximumCachedImages, "250 thumbnails keep the 200 most recent")
        XCTAssertLessThanOrEqual(images.cachedBytes, ExtensionItemImage.maximumCachedBytes)
        images.reset()
        images.request("https://icons.example.com/0-0.png", for: ext)
        XCTAssertEqual(pending().count, 1, "The oldest entries were evicted")
        images.request("https://icons.example.com/9-24.png", for: ext)
        XCTAssertEqual(pending().count, 1, "The newest are still cached")
    }

    func testTheByteBoundEvictsBeforeTheCountBound() throws {
        let ext = try fixtureExtension()
        let images = ExtensionRowImages()
        let large = NSImage(cgImage: ExtensionImageFixtures.cgImage(width: 64, height: 64, ExtensionImageFixtures.red), size: NSSize(width: 512, height: 512))
        images.load = { _, _, done in done(.image(large)) }
        images.authorize = { _, _ in true }
        images.request("https://icons.example.com/a.png", for: ext)
        images.request("https://icons.example.com/b.png", for: ext)
        images.request("https://icons.example.com/c.png", for: ext)
        XCTAssertLessThanOrEqual(images.cachedBytes, ExtensionItemImage.maximumCachedBytes)
        XCTAssertEqual(images.cachedCount, 3, "Three 1 MB entries fit in 4 MB")
        images.request("https://icons.example.com/d.png", for: ext)
        images.request("https://icons.example.com/e.png", for: ext)
        XCTAssertEqual(images.cachedCount, 4, "A fifth evicts the oldest")
    }
}
