import ImageIO
import UniformTypeIdentifiers
import VolantCore
import XCTest
@testable import Volant

/// The fetch helper's row image thumbnails (`ExtensionImageDecoding.thumbnailPNG`, which runs in
/// VolantFetchHost) from real images of every accepted format, the inputs it refuses, and the app's
/// PNG-only acceptance of what the helper returns (`ExtensionRowImages.thumbnail`).
final class ExtensionRowImageThumbnailTests: XCTestCase {
    private typealias Fixtures = ExtensionImageFixtures

    /// Asserts `data` becomes a PNG thumbnail of `width` by `height` whose center is `color`, which the
    /// app then accepts.
    private func assertThumbnail(_ data: Data?, _ label: String, width: Int = 16, height: Int = 16, color: Fixtures.Color = Fixtures.blue,
                                 file: StaticString = #filePath, line: UInt = #line) {
        guard let data else { return XCTFail("\(label): no source image", file: file, line: line) }
        guard let png = ExtensionImageDecoding.thumbnailPNG(data) else { return XCTFail("\(label): no thumbnail", file: file, line: line) }
        XCTAssertEqual(ExtensionImageFormat.detect(png), .png, label, file: file, line: line)
        XCTAssertLessThanOrEqual(png.count, ExtensionItemImage.maximumThumbnailBytes, label, file: file, line: line)
        guard let decoded = Fixtures.inspect(png) else { return XCTFail("\(label): thumbnail does not decode", file: file, line: line) }
        XCTAssertEqual(decoded.width, width, label, file: file, line: line)
        XCTAssertEqual(decoded.height, height, label, file: file, line: line)
        XCTAssertTrue(Fixtures.close(decoded.center, color), "\(label): center \(decoded.center) is not \(color)", file: file, line: line)
        XCTAssertNotNil(ExtensionRowImages.thumbnail(png), "\(label): the app accepts the helper's thumbnail", file: file, line: line)
    }

    func testEveryAcceptedFormatBecomesASmallPNG() {
        assertThumbnail(Fixtures.image(.png), "PNG")
        assertThumbnail(Fixtures.image(.jpeg), "JPEG")
        assertThumbnail(Fixtures.image(.gif), "GIF")
        assertThumbnail(Fixtures.image(.bmp), "BMP")
        assertThumbnail(Fixtures.image(.tiff), "TIFF")
        assertThumbnail(Fixtures.ico([Fixtures.icoPNGEntry(size: 16, Fixtures.blue)]), "ICO with a PNG entry")
        assertThumbnail(Fixtures.ico([Fixtures.icoBMPEntry(size: 16, Fixtures.blue)]), "ICO with a BMP entry")
        let webp = try? XCTUnwrap(Fixtures.inspect(Fixtures.webp))
        assertThumbnail(Fixtures.webp, "WebP fixture", width: webp?.width ?? 0, height: webp?.height ?? 0, color: webp?.center ?? Fixtures.blue)
    }

    func testAVIFAndHEICWhenThisMacCanWriteThem() throws {
        var written = 0
        for (type, label) in [(UTType("public.avif")!, "AVIF"), (UTType.heic, "HEIC")] {
            guard let data = Fixtures.image(type, width: 64, height: 64) else { continue }
            written += 1
            XCTAssertEqual(ExtensionImageFormat.detect(data), label == "AVIF" ? .avif : .heic, label)
            assertThumbnail(data, label, width: 64, height: 64)
        }
        if written == 0 { throw XCTSkip("This macOS writes neither AVIF nor HEIC; their signatures are covered in ExtensionItemCopyTests") }
    }

    func testLargeImagesShrinkKeepingTheirShape() {
        assertThumbnail(Fixtures.image(.png, width: 256, height: 64), "wide PNG", width: 64, height: 16)
        assertThumbnail(Fixtures.image(.jpeg, width: 100, height: 400), "tall JPEG", width: 16, height: 64)
    }

    func testGIFsUseTheFirstFrameAndICOsTheirLargestEntry() {
        assertThumbnail(Fixtures.animatedGIF(first: Fixtures.red, second: Fixtures.blue), "animated GIF", color: Fixtures.red)
        let ico = Fixtures.ico([Fixtures.icoPNGEntry(size: 16, Fixtures.red), Fixtures.icoBMPEntry(size: 48, Fixtures.green), Fixtures.icoPNGEntry(size: 32, Fixtures.blue)])
        assertThumbnail(ico, "ICO with three entries", width: 48, height: 48, color: Fixtures.green)
    }

    func testSVGGarbageAndOversizedImagesAreRefused() throws {
        let png = try XCTUnwrap(Fixtures.image(.png))
        let refused: [(String, Data)] = [
            ("SVG", Data(#"<svg xmlns="http://www.w3.org/2000/svg" width="16" height="16"><rect width="16" height="16"/></svg>"#.utf8)),
            ("SVG with a prolog", Data("<?xml version=\"1.0\"?><svg xmlns=\"http://www.w3.org/2000/svg\"/>".utf8)),
            ("HTML error page", Data("<!doctype html><title>Not found</title>".utf8)),
            ("PDF", Data("%PDF-1.4\n%âãÏÓ\n1 0 obj<<>>endobj".utf8)),
            ("random bytes", Data((0..<512).map { UInt8(truncatingIfNeeded: $0 &* 37 &+ 11) })),
            ("PNG signature then garbage", png.prefix(8) + Data(repeating: 0xAB, count: 200)),
            ("truncated PNG header", png.prefix(20)),
            ("empty", Data()),
            ("too wide", try XCTUnwrap(Fixtures.image(.png, width: ExtensionItemImage.maximumSourceDimension + 1, height: 1))),
            ("too many pixels", try XCTUnwrap(Fixtures.image(.png, width: 4000, height: 4001)))
        ]
        for (label, data) in refused {
            XCTAssertNil(ExtensionImageDecoding.thumbnailPNG(data), label)
        }
        XCTAssertNotNil(ExtensionImageDecoding.thumbnailPNG(try XCTUnwrap(Fixtures.image(.png, width: 4000, height: 4000))),
                        "16 million pixels is within the bounds")
    }

    func testTheAppAcceptsOnlySmallSingleFramePNGs() throws {
        XCTAssertNotNil(ExtensionRowImages.thumbnail(try XCTUnwrap(Fixtures.image(.png, width: 64, height: 64))))
        XCTAssertNotNil(ExtensionRowImages.thumbnail(try XCTUnwrap(Fixtures.image(.png, width: 1, height: 64))))
        let refused: [(String, Data?)] = [
            ("65 pixels wide", Fixtures.image(.png, width: 65, height: 10)),
            ("65 pixels tall", Fixtures.image(.png, width: 10, height: 65)),
            ("JPEG", Fixtures.image(.jpeg)),
            ("GIF", Fixtures.image(.gif)),
            ("ICO", Fixtures.ico([Fixtures.icoPNGEntry(size: 16, Fixtures.blue)])),
            ("WebP", Fixtures.webp),
            ("SVG", Data("<svg/>".utf8)),
            ("garbage after a PNG signature", Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]) + Data(repeating: 1, count: 64))
        ]
        for (label, data) in refused { XCTAssertNil(ExtensionRowImages.thumbnail(try XCTUnwrap(data, label)), label) }
        let padded = try XCTUnwrap(Fixtures.image(.png)) + Data(repeating: 0, count: ExtensionItemImage.maximumThumbnailBytes)
        XCTAssertNil(ExtensionRowImages.thumbnail(padded), "Over the byte limit, even when it decodes")
    }
}
