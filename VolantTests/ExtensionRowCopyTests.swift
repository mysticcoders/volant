import ImageIO
import UniformTypeIdentifiers
import VolantCore
import XCTest
@testable import Volant

/// Rows that copy text, SVG or images with the `clipboard-write` permission, with a fake fetch helper in
/// place of VolantFetchHost and a fake clipboard. Every file and download is temporary and fictional.
@MainActor
final class ExtensionRowCopyTests: XCTestCase {
    private var root: URL!
    private var config: URL { root.appendingPathComponent("config.json") }
    private var folder: URL { root.appendingPathComponent("logos", isDirectory: true) }
    private let host = "assets.example.com"
    /// A fictional solid-color WebP, the same one the launcher fixtures use as an icon.
    private let webp = Data(base64Encoded: "UklGRh4AAABXRUJQVlA4TBEAAAAvH8AHAAdQvKIUuf+BiOh/AAA=")!

    private var written: [ExtensionCopyContent] = []
    private var fetched: [(ExtensionRequest, [String])] = []
    private var reply: (Data?, Int) = (nil, 0)
    private var activity = ExtensionActivityRecorder()

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("row-copy-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try Data(#"{"extensions":{},"communityExtensionsAllowed":true}"#.utf8).write(to: config)
        written = []; fetched = []; activity = ExtensionActivityRecorder()
    }

    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: root) }

    private func writeManifest(permissions: [String]?) throws {
        let module = Data([0, 97, 115, 109, 1, 0, 0, 0, 5, 4, 1, 1, 1, 1])
        try module.write(to: folder.appendingPathComponent("logos.wasm"))
        let manifest = ExtensionManifest(id: "community.fictional.logos", name: "Fictional Logos", version: "1", module: "logos.wasm",
                                         capabilities: [], timeoutSeconds: 2, sha256: Integrity.sha256(module), hosts: [host], output: "items",
                                         permissions: permissions)
        try JSONEncoder().encode(manifest).write(to: folder.appendingPathComponent("manifest.json"))
    }

    /// One installed list extension on `assets.example.com`, enabled, with fakes for the clipboard and fetch.
    private func manager(permissions: [String]? = ["clipboard-write"]) throws -> (ExtensionManager, InstalledExtension) {
        try writeManifest(permissions: permissions)
        let manager = ExtensionManager(configURL: config, roots: [folder], dataDirectory: root.appendingPathComponent("ExtensionData"))
        manager.reload()
        try manager.setEnabled(try XCTUnwrap(manager.extensions.first), true)
        manager.activity = activity
        manager.writeClipboard = { [unowned self] in written.append($0) }
        manager.fetchCopy = { [unowned self] request, hosts, completion in
            fetched.append((request, hosts)); completion(reply.0, reply.1)
        }
        return (manager, try XCTUnwrap(manager.extensions.first))
    }

    private func copy(_ manager: ExtensionManager, _ ext: InstalledExtension, _ copy: ExtensionItemCopy) -> Result<String, Error> {
        var outcome: Result<String, Error>?
        manager.copy(ext, item: ExtensionItem(title: "Fictional logo", copy: copy)) { outcome = $0 }
        return outcome!
    }

    private func image(_ type: UTType) throws -> Data {
        let context = try XCTUnwrap(CGContext(data: nil, width: 16, height: 16, bitsPerComponent: 8, bytesPerRow: 0,
                                              space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(red: 0.2, green: 0.4, blue: 0.8, alpha: 1); context.fill(CGRect(x: 0, y: 0, width: 16, height: 16))
        let data = NSMutableData()
        let destination = try XCTUnwrap(CGImageDestinationCreateWithData(data, type.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(destination, try XCTUnwrap(context.makeImage()), nil)
        XCTAssertTrue(CGImageDestinationFinalize(destination))
        return data as Data
    }

    private func url(_ type: String) -> ExtensionItemCopy { ExtensionItemCopy(url: "https://\(host)/logo", type: type, title: "Copy Logo") }

    private func events(_ operation: ExtensionActivity.Operation) -> [ExtensionActivity] { activity.log.events.filter { $0.operation == operation } }

    func testTextCopiesWithoutFetchingAndRecordsNoContent() throws {
        let (manager, ext) = try manager()
        let svg = #"<svg xmlns="http://www.w3.org/2000/svg"><circle r="4"/></svg>"#
        XCTAssertEqual(try copy(manager, ext, ExtensionItemCopy(text: svg, title: "Copy SVG")).get(), "Copied SVG")
        XCTAssertEqual(written, [.text(svg)])
        XCTAssertTrue(fetched.isEmpty)
        XCTAssertEqual(events(.clipboardWrite).map(\.outcome), [.completed])
        XCTAssertNil(events(.clipboardWrite).first?.detail, "A text copy records no detail, never its content")
    }

    func testDownloadedSVGAndTextCopyAsPlainText() throws {
        let (manager, ext) = try manager()
        reply = (Data("\u{FEFF}<?xml version=\"1.0\"?>\n<svg/>".utf8), 200)
        XCTAssertEqual(try copy(manager, ext, url("svg")).get(), "Copied Logo")
        XCTAssertEqual(written, [.text("<?xml version=\"1.0\"?>\n<svg/>")], "A leading byte order mark is never copied")
        XCTAssertEqual(fetched.first?.0.url.absoluteString, "https://assets.example.com/logo")
        XCTAssertEqual(fetched.first?.0.method, "GET")
        XCTAssertEqual(fetched.first?.1, [host], "The helper gets only approved declared hosts")
        reply = (Data("Fictional notes".utf8), 200)
        XCTAssertNoThrow(try copy(manager, ext, url("text")).get())
        XCTAssertEqual(written.last, .text("Fictional notes"))
        XCTAssertEqual(events(.fetch).map(\.detail), [host, host])
        XCTAssertEqual(events(.clipboardWrite).map(\.detail), [host, host], "Clipboard writes name only the host")
    }

    func testEachImageTypeDecodesAndCopiesAsPNGAndTIFF() throws {
        let (manager, ext) = try manager()
        let images: [(String, Data)] = [("png", try image(.png)), ("jpeg", try image(.jpeg)), ("webp", webp), ("ico", try image(.ico))]
        for (type, data) in images {
            reply = (data, 200)
            XCTAssertNoThrow(try copy(manager, ext, ExtensionItemCopy(url: "https://\(host)/logo", type: type)).get(), type)
            guard case .image(let png, let tiff)? = written.last else { XCTFail("\(type) copied no image"); continue }
            let decoded = try XCTUnwrap(CGImageSourceCreateWithData(png as CFData, nil))
            XCTAssertEqual(CGImageSourceGetType(decoded) as String?, UTType.png.identifier, type)
            XCTAssertNotNil(CGImageSourceCreateWithData(tiff as CFData, nil).flatMap { CGImageSourceCreateImageAtIndex($0, 0, nil) }, type)
        }
        XCTAssertEqual(written.count, 4)
        reply = (images[0].1, 200)
        XCTAssertEqual(try copy(manager, ext, ExtensionItemCopy(url: "https://\(host)/logo", type: "png")).get(), "Copied image")
    }

    func testTheImageTypeCopiesAnyFormatVolantDecodes() throws {
        let (manager, ext) = try manager()
        typealias Fixtures = ExtensionImageFixtures
        var images: [(String, Data)] = [("PNG", try image(.png)), ("JPEG", try image(.jpeg)), ("GIF", try image(.gif)), ("BMP", try image(.bmp)),
                                        ("TIFF", try image(.tiff)), ("WebP", webp),
                                        ("ICO with a PNG entry", Fixtures.ico([Fixtures.icoPNGEntry(size: 16, Fixtures.blue)])),
                                        ("ICO with a BMP entry", Fixtures.ico([Fixtures.icoBMPEntry(size: 16, Fixtures.blue)]))]
        if let avif = Fixtures.image(UTType("public.avif")!) { images.append(("AVIF", avif)) }
        if let heic = Fixtures.image(.heic, width: 64, height: 64) { images.append(("HEIC", heic)) }
        for (label, data) in images {
            reply = (data, 200)
            XCTAssertNoThrow(try copy(manager, ext, ExtensionItemCopy(url: "https://\(host)/favicon", type: "image")).get(), label)
            guard case .image(let png, _)? = written.last else { XCTFail("\(label) copied no image"); continue }
            XCTAssertEqual(CGImageSourceCreateWithData(png as CFData, nil).flatMap(CGImageSourceGetType) as String?, UTType.png.identifier, label)
        }
        reply = (Data("\u{FEFF}<svg xmlns=\"http://www.w3.org/2000/svg\"/>".utf8), 200)
        XCTAssertEqual(try copy(manager, ext, ExtensionItemCopy(url: "https://\(host)/favicon", type: "image", title: "Copy Favicon")).get(), "Copied Favicon")
        XCTAssertEqual(written.last, .text("<svg xmlns=\"http://www.w3.org/2000/svg\"/>"), "SVG under image is copied as text, never rendered")
        for (label, data) in [("HTML", Data("<html><body>Not found</body></html>".utf8)), ("PDF", Data("%PDF-1.4".utf8)), ("truncated PNG", try image(.png).prefix(20))] {
            reply = (data, 200)
            XCTAssertThrowsError(try copy(manager, ext, ExtensionItemCopy(url: "https://\(host)/favicon", type: "image")).get(), label) {
                XCTAssertEqual($0 as? ExtensionCopyError, .wrongType(.image))
            }
        }
    }

    func testGIFBMPAndAVIFAreExplicitTypesThatStayStrict() throws {
        let (manager, ext) = try manager()
        let animated = ExtensionImageFixtures.animatedGIF(first: ExtensionImageFixtures.red, second: ExtensionImageFixtures.blue)
        reply = (animated, 200)
        XCTAssertNoThrow(try copy(manager, ext, url("gif")).get())
        guard case .image(let png, _)? = written.last else { return XCTFail("The GIF copied no image") }
        XCTAssertTrue(ExtensionImageFixtures.close(try XCTUnwrap(ExtensionImageFixtures.inspect(png)).center, ExtensionImageFixtures.red), "A GIF copies its first frame")
        reply = (try image(.bmp), 200)
        XCTAssertNoThrow(try copy(manager, ext, url("bmp")).get())
        if let avif = ExtensionImageFixtures.image(UTType("public.avif")!) {
            reply = (avif, 200)
            XCTAssertNoThrow(try copy(manager, ext, url("avif")).get())
        }
        for (type, data) in [("gif", try image(.png)), ("bmp", try image(.gif)), ("avif", try image(.png)), ("png", try image(.gif)), ("ico", try image(.bmp))] {
            reply = (data, 200)
            XCTAssertThrowsError(try copy(manager, ext, url(type)).get(), type) {
                XCTAssertEqual($0 as? ExtensionCopyError, .wrongType(ExtensionItemCopy.Kind(rawValue: type)!))
            }
        }
    }

    func testAnICOCopiesItsLargestEntry() throws {
        let (manager, ext) = try manager()
        typealias Fixtures = ExtensionImageFixtures
        reply = (Fixtures.ico([Fixtures.icoPNGEntry(size: 16, Fixtures.red), Fixtures.icoBMPEntry(size: 48, Fixtures.green), Fixtures.icoPNGEntry(size: 32, Fixtures.blue)]), 200)
        XCTAssertNoThrow(try copy(manager, ext, url("ico")).get())
        guard case .image(let png, _)? = written.last else { return XCTFail("The ICO copied no image") }
        let copied = try XCTUnwrap(Fixtures.inspect(png))
        XCTAssertEqual(copied.width, 48)
        XCTAssertTrue(Fixtures.close(copied.center, Fixtures.green))
    }

    func testWrongTypesCopyNothing() throws {
        let (manager, ext) = try manager()
        let png = try image(.png), jpeg = try image(.jpeg)
        let cases: [(String, Data)] = [("svg", png), ("svg", Data("<html><body/></html>".utf8)), ("png", jpeg), ("jpeg", png), ("webp", png),
                                       ("ico", png), ("png", Data("<svg/>".utf8)), ("text", Data([0xFF, 0xFE, 0x00])),
                                       ("png", png.prefix(20))]
        for (type, data) in cases {
            reply = (data, 200)
            guard case .failure(let error) = copy(manager, ext, url(type)) else { XCTFail("\(type) accepted wrong bytes"); continue }
            XCTAssertEqual(error as? ExtensionCopyError, .wrongType(ExtensionItemCopy.Kind(rawValue: type)!))
        }
        XCTAssertTrue(written.isEmpty)
        XCTAssertEqual(Set(events(.clipboardWrite).map(\.outcome)), [.failed])
    }

    func testOversizedAndFailedDownloadsCopyNothing() throws {
        let (manager, ext) = try manager()
        reply = (Data("<svg/>".utf8) + Data(repeating: 0x20, count: ExtensionItemCopy.maximumDownloadBytes), 200)
        XCTAssertThrowsError(try copy(manager, ext, url("svg")).get()) { XCTAssertEqual($0 as? ExtensionCopyError, .tooLarge) }
        reply = (nil, 0)
        XCTAssertThrowsError(try copy(manager, ext, url("svg")).get()) { XCTAssertEqual($0 as? ExtensionCopyError, .unavailable(0)) }
        reply = (Data("<svg/>".utf8), 404)
        XCTAssertThrowsError(try copy(manager, ext, url("svg")).get()) { XCTAssertEqual($0 as? ExtensionCopyError, .unavailable(404)) }
        XCTAssertTrue(written.isEmpty)
        XCTAssertEqual(events(.fetch).map(\.outcome), [.completed, .failed, .completed])
    }

    func testUnapprovedOrUndeclaredHostsAreNeverFetched() throws {
        let (manager, ext) = try manager()
        try ExtensionHostApprovals.remove(host, at: config)
        XCTAssertThrowsError(try copy(manager, ext, url("svg")).get()) { XCTAssertEqual($0 as? ExtensionCopyError, .hostNotApproved(self.host)) }
        XCTAssertThrowsError(try copy(manager, ext, ExtensionItemCopy(url: "https://other.example.com/logo.svg", type: "svg")).get()) {
            XCTAssertEqual($0 as? ExtensionCopyError, .notAllowed, "A copy on an undeclared host never survives sanitizing")
        }
        XCTAssertTrue(fetched.isEmpty && written.isEmpty)
        XCTAssertEqual(events(.clipboardWrite).map(\.outcome), [.denied, .denied])
    }

    func testAHostRemovedDuringTheDownloadCopiesNothing() throws {
        let (manager, ext) = try manager()
        manager.fetchCopy = { [unowned self] _, _, completion in
            try? ExtensionHostApprovals.remove(host, at: config)
            completion(Data("<svg/>".utf8), 200)
        }
        XCTAssertThrowsError(try copy(manager, ext, url("svg")).get()) { XCTAssertEqual($0 as? ExtensionCopyError, .hostNotApproved(self.host)) }
        XCTAssertTrue(written.isEmpty)
    }

    func testDisabledBlockedRevokedOrUnpermittedExtensionsCopyNothing() throws {
        let (manager, ext) = try manager()
        try manager.setCommunityAllowed(false, expected: true)
        XCTAssertThrowsError(try copy(manager, ext, ExtensionItemCopy(text: "x")).get()) {
            guard case .communityDisabled? = $0 as? ExtensionManager.ExtensionError else { return XCTFail("\($0)") }
        }
        try manager.setCommunityAllowed(true, expected: false)
        manager.fetchCopy = { _, _, completion in
            try? manager.setCommunityAllowed(false, expected: true)
            completion(Data("<svg/>".utf8), 200)
        }
        XCTAssertThrowsError(try copy(manager, ext, url("svg")).get(), "The master switch is checked again after the download")
        try manager.setCommunityAllowed(true, expected: false)
        try manager.setEnabled(ext, false)
        XCTAssertThrowsError(try copy(manager, ext, ExtensionItemCopy(text: "x")).get()) {
            guard case .disabled? = $0 as? ExtensionManager.ExtensionError else { return XCTFail("\($0)") }
        }
        try manager.setEnabled(try XCTUnwrap(manager.extensions.first), true)
        let revoked = ExtensionCatalog.Revocation(id: ext.id, sha256: try XCTUnwrap(ext.manifest.sha256), reason: "Fictional reason.")
        try ExtensionCatalogState.recordRevocations([revoked], sequence: 1, at: manager.catalogStateURL)
        XCTAssertThrowsError(try copy(manager, ext, ExtensionItemCopy(text: "x")).get()) {
            guard case .revoked? = $0 as? ExtensionManager.ExtensionError else { return XCTFail("\($0)") }
        }
        XCTAssertTrue(written.isEmpty)

        try FileManager.default.removeItem(at: manager.catalogStateURL)
        let (plain, plainExt) = try self.manager(permissions: nil)
        XCTAssertThrowsError(try copy(plain, plainExt, ExtensionItemCopy(text: "x")).get()) { XCTAssertEqual($0 as? ExtensionCopyError, .notAllowed) }
        XCTAssertTrue(written.isEmpty)
    }

    func testListRunsKeepCopiesOnlyWithThePermissionAndNeverFetchThem() throws {
        let plan = #"{"items":[{"title":"Logo","copy":{"url":"https://assets.example.com/logo.svg","type":"svg","title":"Copy SVG"}}]}"#
        for (permissions, kept) in [(["clipboard-write"], true), (nil, false)] as [([String]?, Bool)] {
            let (manager, ext) = try manager(permissions: permissions)
            var listed: [ExtensionItem]?
            manager.invokeOverride = { _, _, completion in completion(.success(plan)) }
            manager.runItems(ext, query: "", fetch: { _, _, _ in XCTFail("No fetch") }) { listed = try? $0.get() }
            XCTAssertEqual(listed?.first?.copy != nil, kept)
        }
        XCTAssertTrue(fetched.isEmpty, "Listing never downloads a copy")
    }

    func testClipboardWriteIsPartOfTheApprovalAndShownToTheOwner() throws {
        let (manager, ext) = try manager(permissions: nil)
        XCTAssertTrue(ext.enabled)
        let without = try ExtensionApproval.fingerprint(ext.manifest)
        try writeManifest(permissions: ["clipboard-write"])
        manager.reload()
        let added = try XCTUnwrap(manager.extensions.first)
        XCTAssertNotEqual(try ExtensionApproval.fingerprint(added.manifest), without)
        XCTAssertFalse(added.enabled, "Adding clipboard-write needs enabling again")
        XCTAssertFalse(added.manifest.requestsNoMoreThan(ext.manifest), "A catalog update that adds it turns the extension off")
        XCTAssertTrue(added.accessDescription.contains("Copy text and images to your clipboard when you choose them"), added.accessDescription)
        XCTAssertFalse(ext.accessDescription.contains("Copy text and images"))
    }
}
