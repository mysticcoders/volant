import AppKit
import VolantCore
import XCTest
@testable import Volant

/// SVG row image previews in the app: markup the fetch helper marked as SVG goes, unread, to the extension
/// helper (`ExtensionManager.rasterizeSVG`), only its PNG is shown, refusals, timeouts and failures keep
/// the placeholder and are cached like any failed image, and activity records the host and the outcome,
/// never the markup. Fake fetch and extension helpers stand in; every file is temporary and fictional.
@MainActor
final class ExtensionRowImageSVGTests: XCTestCase {
    private var root: URL!
    private var config: URL { root.appendingPathComponent("config.json") }
    private var folder: URL { root.appendingPathComponent("logos", isDirectory: true) }
    private let host = "logos.example.com"
    private let markup = Data(#"<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24"><path d="M0 0h24v24H0z"/></svg>"#.utf8)
    private var fetches = 0
    private var reply: ExtensionFetcher.RowImageReply = .stopped
    private var drawn: [Data] = []
    private var drawReply: ExtensionSVGRendering.Reply = .failed
    private var activity = ExtensionActivityRecorder()

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("row-svg-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try Data(#"{"extensions":{},"communityExtensionsAllowed":true}"#.utf8).write(to: config)
        fetches = 0; drawn = []; activity = ExtensionActivityRecorder()
        reply = .svg(markup)
        drawReply = .png(try XCTUnwrap(ExtensionImageFixtures.image(.png, width: 24, height: 24)))
    }

    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: root) }

    /// One enabled list extension with `row-images` on `logos.example.com`, with fake helpers.
    private func manager() throws -> (ExtensionManager, InstalledExtension) {
        let module = Data([0, 97, 115, 109, 1, 0, 0, 0, 5, 4, 1, 1, 1, 1])
        try module.write(to: folder.appendingPathComponent("logos.wasm"))
        let manifest = ExtensionManifest(id: "community.fictional.logos", name: "Fictional Logos", version: "1", module: "logos.wasm", capabilities: [],
                                         timeoutSeconds: 2, sha256: Integrity.sha256(module), hosts: [host], output: "items", permissions: ["row-images"])
        try JSONEncoder().encode(manifest).write(to: folder.appendingPathComponent("manifest.json"))
        let manager = ExtensionManager(configURL: config, roots: [folder], dataDirectory: root.appendingPathComponent("ExtensionData"))
        manager.reload()
        try manager.setEnabled(try XCTUnwrap(manager.extensions.first), true)
        manager.activity = activity
        manager.fetchRowImage = { [unowned self] _, _, completion in fetches += 1; completion(reply) }
        manager.rasterizeSVG = { [unowned self] data, completion in drawn.append(data); completion(drawReply) }
        return (manager, try XCTUnwrap(manager.extensions.first))
    }

    private func load(_ manager: ExtensionManager, _ ext: InstalledExtension) -> String {
        var outcome = "none"
        manager.loadRowImage(ext, url: "https://logos.example.com/brand.svg") {
            switch $0 {
            case .image: outcome = "image"
            case .failed: outcome = "failed"
            case .refused: outcome = "refused"
            case .stopped: outcome = "stopped"
            }
        }
        return outcome
    }

    private func events(_ operation: ExtensionActivity.Operation) -> [ExtensionActivity] { activity.log.events.filter { $0.operation == operation } }

    func testSVGGoesUnreadToTheExtensionHelperAndOnlyItsPNGIsShown() throws {
        let (manager, ext) = try manager()
        XCTAssertEqual(load(manager, ext), "image")
        XCTAssertEqual(drawn, [markup], "The fetch helper's bytes reach the extension helper unchanged")
        XCTAssertEqual(events(.fetch).map(\.outcome), [.completed])
        XCTAssertEqual(events(.fetch).map(\.detail), [host])
        XCTAssertEqual(events(.svgRender).map(\.outcome), [.completed])
        XCTAssertEqual(events(.svgRender).map(\.detail), [nil], "The outcome is recorded without any of the markup")
    }

    func testRefusalsTimeoutsAndFailuresShowThePlaceholder() throws {
        let (manager, ext) = try manager()
        reply = .svgRefused
        XCTAssertEqual(load(manager, ext), "failed", "The fetch helper refused the markup")
        XCTAssertTrue(drawn.isEmpty, "Refused markup never reaches the extension helper")
        reply = .svg(markup)
        for (helperReply, outcome) in [(ExtensionSVGRendering.Reply.refused, ExtensionActivity.Outcome.denied), (.timedOut, .timedOut), (.failed, .failed)] {
            drawReply = helperReply
            XCTAssertEqual(load(manager, ext), "failed", "\(helperReply)")
            XCTAssertEqual(events(.svgRender).last?.outcome, outcome)
        }
        drawReply = .png(try XCTUnwrap(ExtensionImageFixtures.image(.jpeg, width: 24, height: 24)))
        XCTAssertEqual(load(manager, ext), "failed", "Only a PNG from the helper is accepted")
        drawReply = .png(try XCTUnwrap(ExtensionImageFixtures.image(.png, width: 128, height: 128)))
        XCTAssertEqual(load(manager, ext), "failed", "Never larger than 64 pixels")
        XCTAssertEqual(events(.svgRender).map(\.outcome), [.denied, .denied, .timedOut, .failed, .failed, .failed])
    }

    func testAnExtensionTurnedOffWhileDrawingShowsNothing() throws {
        let (manager, ext) = try manager()
        var finish: ((ExtensionSVGRendering.Reply) -> Void)?
        manager.rasterizeSVG = { _, completion in finish = completion }
        var outcome: ExtensionManager.RowImageOutcome?
        manager.loadRowImage(ext, url: "https://logos.example.com/brand.svg") { outcome = $0 }
        try manager.setEnabled(ext, false)
        finish?(drawReply)
        guard case .refused? = outcome else { return XCTFail("The image is dropped once the extension is off: \(String(describing: outcome))") }
    }

    func testSVGPreviewsAndTheirFailuresAreCachedLikeOtherImages() throws {
        let (manager, ext) = try manager()
        let images = ExtensionRowImages()
        images.load = { manager.loadRowImage($0, url: $1, completion: $2) }
        images.authorize = { manager.rowImageURL($0, $1) != nil }
        images.request("https://logos.example.com/brand.svg", for: ext)
        XCTAssertNotNil(images.image("https://logos.example.com/brand.svg", for: ext))
        images.reset()
        images.request("https://logos.example.com/brand.svg", for: ext)
        XCTAssertNotNil(images.image("https://logos.example.com/brand.svg", for: ext))
        XCTAssertEqual(drawn.count, 1, "A drawn preview is reused for the session")
        drawReply = .timedOut
        images.request("https://logos.example.com/slow.svg", for: ext)
        images.reset()
        images.request("https://logos.example.com/slow.svg", for: ext)
        XCTAssertEqual(drawn.count, 2, "A file that timed out is not sent to the helper again, so it cannot stop it repeatedly")
        XCTAssertEqual(fetches, 2)
    }

    func testTheHelperReplyIsReadOnlyAsAPNGOrARefusalCode() {
        XCTAssertEqual(ExtensionSVGRendering.reply(png: Data([1]), code: nil), .png(Data([1])))
        XCTAssertEqual(ExtensionSVGRendering.reply(png: nil, code: "refused.declaration"), .refused)
        XCTAssertEqual(ExtensionSVGRendering.reply(png: nil, code: "unavailable"), .failed)
        XCTAssertEqual(ExtensionSVGRendering.reply(png: Data([1]), code: "failed"), .failed)
    }

    func testACallThatGetsNoAnswerTimesOutOnceAndClosesTheConnection() {
        var closed = 0
        var replies: [ExtensionSVGRendering.Reply] = []
        let done = expectation(description: "timed out")
        let call = ExtensionSVGRendering.Call(timeout: 0.05, startTimeout: 5, close: { closed += 1 }) { replies.append($0); done.fulfill() }
        call.armStart()
        call.sent()
        wait(for: [done], timeout: 2)
        call.finish(.png(Data([1])))
        let settle = expectation(description: "settle")
        DispatchQueue.main.async { settle.fulfill() }
        wait(for: [settle], timeout: 1)
        XCTAssertEqual(replies, [.timedOut], "A late answer is ignored")
        XCTAssertEqual(closed, 1)
    }

    func testAHelperThatNeverStartsFails() {
        var replies: [ExtensionSVGRendering.Reply] = []
        let done = expectation(description: "start failed")
        let call = ExtensionSVGRendering.Call(timeout: 5, startTimeout: 0.05, close: {}) { replies.append($0); done.fulfill() }
        call.armStart()
        wait(for: [done], timeout: 2)
        XCTAssertEqual(replies, [.failed])
    }
}
