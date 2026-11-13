import AppKit
import Network
import VolantCore
import XCTest
@testable import Volant

/// The extension helper's SVG previews (`ExtensionSVGRasterizer`, compiled into VolantExtensionHost and
/// these tests, never the app): real logos become small PNGs of the right shape and color, refused markup
/// draws nothing, and the system renderer itself reaches neither the network nor a file even when the
/// check is bypassed. Skips with a reason on a macOS without an SVG image representation.
final class ExtensionSVGRasterizerTests: XCTestCase {
    private typealias Fixtures = ExtensionImageFixtures

    /// Vercel's triangle from svgl (https://svgl.app/library/vercel.svg).
    private let vercel = ##"<svg viewBox="0 0 256 222" width="256" height="222" xmlns="http://www.w3.org/2000/svg" preserveAspectRatio="xMidYMid"><path fill="#000" d="m128 0 128 221.705H0z"/></svg>"##
    /// Figma's logo from svgl (https://svgl.app/library/figma.svg), with its clip path.
    private let figma = ##"""
    <svg width="54" height="80" viewBox="0 0 54 80" fill="none" xmlns="http://www.w3.org/2000/svg">
    <g clip-path="url(#clip0_912_3)">
    <path d="M13.3333 80.0002C20.6933 80.0002 26.6667 74.0268 26.6667 66.6668V53.3335H13.3333C5.97333 53.3335 0 59.3068 0 66.6668C0 74.0268 5.97333 80.0002 13.3333 80.0002Z" fill="#0ACF83"/>
    <path d="M0 39.9998C0 32.6398 5.97333 26.6665 13.3333 26.6665H26.6667V53.3332H13.3333C5.97333 53.3332 0 47.3598 0 39.9998Z" fill="#A259FF"/>
    <path d="M0 13.3333C0 5.97333 5.97333 0 13.3333 0H26.6667V26.6667H13.3333C5.97333 26.6667 0 20.6933 0 13.3333Z" fill="#F24E1E"/>
    <path d="M26.6667 0H40.0001C47.3601 0 53.3334 5.97333 53.3334 13.3333C53.3334 20.6933 47.3601 26.6667 40.0001 26.6667H26.6667V0Z" fill="#FF7262"/>
    <path d="M53.3334 39.9998C53.3334 47.3598 47.3601 53.3332 40.0001 53.3332C32.6401 53.3332 26.6667 47.3598 26.6667 39.9998C26.6667 32.6398 32.6401 26.6665 40.0001 26.6665C47.3601 26.6665 53.3334 32.6398 53.3334 39.9998Z" fill="#1ABCFE"/>
    </g>
    <defs>
    <clipPath id="clip0_912_3">
    <rect width="53.3333" height="80" fill="white"/>
    </clipPath>
    </defs>
    </svg>
    """##
    /// Nike's mark from Simple Icons 16 (https://cdn.jsdelivr.net/npm/simple-icons@16/icons/nike.svg).
    private let nike = ##"<svg role="img" viewBox="0 0 24 24" xmlns="http://www.w3.org/2000/svg"><title>Nike</title><path d="M24 7.8L6.442 15.276c-1.456.616-2.679.925-3.668.925-1.12 0-1.933-.392-2.437-1.177-.317-.504-.41-1.143-.28-1.918.13-.775.476-1.6 1.036-2.478.467-.71 1.232-1.643 2.297-2.8a6.122 6.122 0 00-.784 1.848c-.28 1.195-.028 2.072.756 2.632.373.261.886.392 1.54.392.522 0 1.11-.084 1.764-.252L24 7.8z"/></svg>"##

    private func requireRenderer() throws {
        if ExtensionSVGRasterizer.representationClass == nil {
            throw XCTSkip("This macOS has no SVG image representation, so SVG previews show the placeholder")
        }
    }

    /// The PNG from drawing `svg`, after asserting it is one the app accepts.
    private func png(_ svg: String, file: StaticString = #filePath, line: UInt = #line) throws -> Data {
        guard case .png(let data) = ExtensionSVGRasterizer.rasterize(Data(svg.utf8)) else {
            XCTFail("\(svg.prefix(60)) was not drawn", file: file, line: line); return Data()
        }
        XCTAssertTrue(ExtensionItemImage.looksLikeThumbnail(data), file: file, line: line)
        XCTAssertNotNil(ExtensionRowImages.thumbnail(data), "The app accepts the helper's PNG", file: file, line: line)
        return data
    }

    func testRealLogosBecomeSmallPNGsOfTheirShapeAndColor() throws {
        try requireRenderer()
        let triangle = try XCTUnwrap(Fixtures.inspect(try png(vercel)))
        XCTAssertEqual(triangle.width, 64)
        XCTAssertEqual(triangle.height, 56, "256 by 222 fits 64 pixels wide, keeping its shape")
        XCTAssertTrue(Fixtures.close(triangle.center, Fixtures.Color(red: 0, green: 0, blue: 0)), "Vercel's triangle is black at its center: \(triangle.center)")
        let figmaLogo = try XCTUnwrap(Fixtures.inspect(try png(figma)))
        XCTAssertEqual(figmaLogo.height, 64)
        XCTAssertEqual(figmaLogo.width, 43, "54 by 80 fits 64 pixels tall")
        let swoosh = try XCTUnwrap(Fixtures.inspect(try png(nike)))
        XCTAssertEqual(swoosh.width, 24, "A 24-point icon is not scaled up")
        XCTAssertEqual(swoosh.height, 24)
    }

    func testEveryOutputIsAFreshSmallPNG() throws {
        try requireRenderer()
        let huge = #"<svg xmlns="http://www.w3.org/2000/svg" width="16384" height="4096"><rect width="16384" height="4096" fill="red"/></svg>"#
        let decoded = try XCTUnwrap(Fixtures.inspect(try png(huge)))
        XCTAssertEqual(decoded.width, 64)
        XCTAssertEqual(decoded.height, 16)
        XCTAssertTrue(Fixtures.close(decoded.center, Fixtures.Color(red: 255, green: 0, blue: 0)), "\(decoded.center)")
        XCTAssertEqual(ExtensionSVGRasterizer.draw(Data(vercel.utf8), maximumPixels: 65), .failed, "Never larger than the app accepts")
        XCTAssertEqual(ExtensionSVGRasterizer.draw(Data(#"<svg xmlns="http://www.w3.org/2000/svg"/>"#.utf8), maximumPixels: 64), .failed,
                       "No size, nothing to draw")
    }

    func testRefusedMarkupIsNeverDrawn() throws {
        let hostile = [
            (#"<svg xmlns="http://www.w3.org/2000/svg" onload="alert(1)"/>"#, ExtensionSVGPreview.Refusal.eventAttribute),
            (#"<!DOCTYPE svg SYSTEM "http://127.0.0.1/x.dtd"><svg xmlns="http://www.w3.org/2000/svg"/>"#, .declaration),
            (#"<svg xmlns="http://www.w3.org/2000/svg"><image href="https://evil.example/a.png"/></svg>"#, .forbiddenElement),
            ("%PDF-1.4 not svg", .notSVG)
        ]
        for (svg, refusal) in hostile { XCTAssertEqual(ExtensionSVGRasterizer.rasterize(Data(svg.utf8)), .refused(refusal), svg) }
        XCTAssertEqual(ExtensionSVGRasterizer.Outcome.refused(.declaration).code, "refused.declaration")
    }

    /// Bypasses the check and draws markup full of external references while a loopback listener counts
    /// connections, then confirms the listener does receive a real request, and that a local green PNG
    /// referenced by path never shows up in the drawing.
    func testTheRendererFetchesNothingEvenWhenTheCheckIsBypassed() throws {
        try requireRenderer()
        let connections = Counter()
        let parameters = NWParameters.tcp
        parameters.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: .any)
        let listener: NWListener
        do { listener = try NWListener(using: parameters) } catch { throw XCTSkip("A loopback listener is not allowed here: \(error)") }
        let ready = expectation(description: "listening")
        ready.assertForOverFulfill = false
        listener.newConnectionHandler = { connection in connections.add(); connection.cancel() }
        listener.stateUpdateHandler = { state in
            switch state {
            case .ready, .failed, .cancelled: ready.fulfill()
            default: break
            }
        }
        listener.start(queue: .global())
        defer { listener.stateUpdateHandler = nil; listener.newConnectionHandler = nil; listener.cancel() }
        guard XCTWaiter().wait(for: [ready], timeout: 5) == .completed, case .ready = listener.state, let port = listener.port?.rawValue else {
            throw XCTSkip("A loopback listener could not start here (the sandboxed test host has no network); tools/check-extensions.sh runs this check unsandboxed")
        }
        let green = FileManager.default.temporaryDirectory.appendingPathComponent("svg-green-\(UUID().uuidString).png")
        try XCTUnwrap(Fixtures.image(.png, width: 24, height: 24, Fixtures.green)).write(to: green)
        defer { try? FileManager.default.removeItem(at: green) }
        let base = "http://127.0.0.1:\(port)"
        let open = #"<svg xmlns="http://www.w3.org/2000/svg" xmlns:xlink="http://www.w3.org/1999/xlink" viewBox="0 0 24 24" width="24" height="24">"#
        let documents = [
            open + #"<image href="\#(base)/image.png" width="24" height="24"/></svg>"#,
            open + #"<image xlink:href="\#(base)/xlink.png" width="24" height="24"/></svg>"#,
            open + #"<use href="\#(base)/sprite.svg#a"/><use xlink:href="\#(base)/sprite-xlink.svg#a"/></svg>"#,
            open + #"<style>@import url(\#(base)/import.css); rect { fill: url(\#(base)/paint.svg#g) }</style><rect width="24" height="24"/></svg>"#,
            open + #"<style>@font-face { font-family: f; src: url(\#(base)/font.woff) }</style><text font-family="f" y="20">A</text></svg>"#,
            open + #"<filter id="f"><feImage href="\#(base)/feimage.png"/></filter><rect width="24" height="24" filter="url(#f)"/></svg>"#,
            #"<?xml version="1.0"?><!DOCTYPE svg [<!ENTITY x SYSTEM "\#(base)/xxe.txt"><!ENTITY y SYSTEM "\#(green.absoluteString)">]>"#
                + open + "<text y=\"20\">&x;&y;</text></svg>",
            #"<?xml version="1.0"?><!DOCTYPE svg SYSTEM "\#(base)/svg.dtd">"# + open + "</svg>",
            open + #"<xi:include xmlns:xi="http://www.w3.org/2001/XInclude" href="\#(base)/include.svg"/></svg>"#,
            open + #"<script>fetch('\#(base)/script')</script><a href="\#(base)/link"><rect width="1" height="1" onload="fetch('\#(base)/onload')"/></a></svg>"#,
            open + #"<foreignObject width="24" height="24"><img xmlns="http://www.w3.org/1999/xhtml" src="\#(base)/fo.png"/></foreignObject></svg>"#
        ]
        for svg in documents {
            XCTAssertNotNil(ExtensionSVGPreview.check(Data(svg.utf8)), "The check refuses it: \(svg)")
            _ = ExtensionSVGRasterizer.draw(Data(svg.utf8), maximumPixels: 64)
        }
        for href in [green.absoluteString, green.path] {
            let svg = open + #"<image href="\#(href)" width="24" height="24"/><image xlink:href="\#(href)" width="24" height="24"/></svg>"#
            if case .png(let data) = ExtensionSVGRasterizer.draw(Data(svg.utf8), maximumPixels: 64), let center = Fixtures.inspect(data)?.center {
                XCTAssertFalse(Fixtures.close(center, Fixtures.green, tolerance: 40), "The renderer drew a local file: \(center)")
            }
        }
        Thread.sleep(forTimeInterval: 1)
        XCTAssertEqual(connections.value, 0, "The renderer opened no connection")
        let probe = expectation(description: "probe")
        URLSession(configuration: .ephemeral).dataTask(with: URL(string: base + "/probe")!) { _, _, _ in probe.fulfill() }.resume()
        wait(for: [probe], timeout: 10)
        XCTAssertGreaterThan(connections.value, 0, "The listener does see a real request, so the zero above is meaningful")
    }

    /// A file the check accepts that the renderer needs well over `renderTimeout` for, which is why the
    /// helper stops itself; `tools/check-extensions.sh` confirms the helper's watchdog exits on it.
    func testAPathologicalFileThatPassesTheCheckOutlastsTheTimeout() throws {
        try requireRenderer()
        var path = "M0 0"
        for index in 0..<3000 { path += "L\((index * 7919) % 16384) \((index * 104729) % 16384)" }
        let svg = #"<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 16384 16384"><path fill-rule="evenodd" d=""# + path + #""/></svg>"#
        XCTAssertNil(ExtensionSVGPreview.check(Data(svg.utf8)), "Size, element and dimension limits all pass")
        let start = Date()
        _ = ExtensionSVGRasterizer.draw(Data(svg.utf8), maximumPixels: 64)
        let elapsed = Date().timeIntervalSince(start)
        if elapsed <= ExtensionSVGPreview.renderTimeout {
            throw XCTSkip("This Mac drew the pathological file in \(elapsed) s, under the timeout")
        }
    }

    /// Counts loopback connections from the listener's queue.
    private final class Counter: @unchecked Sendable {
        private let lock = NSLock()
        private var count = 0
        var value: Int { lock.lock(); defer { lock.unlock() }; return count }
        func add() { lock.lock(); count += 1; lock.unlock() }
    }
}
