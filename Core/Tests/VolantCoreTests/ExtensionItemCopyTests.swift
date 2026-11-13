import XCTest

@testable import VolantCore

/// The `clipboard-write` permission and a row's `copy`: who may declare it, how sanitizing keeps or drops
/// it, and the checks downloaded SVG, text and image bytes must pass before Volant copies them.
final class ExtensionItemCopyTests: XCTestCase {
    private let hosts: Set<String> = ["assets.example.com"]

    private func manifest(output: String? = "items", permissions: [String]? = ["clipboard-write"]) -> ExtensionManifest {
        ExtensionManifest(id: "community.fictional.logos", name: "Fictional Logos", version: "1", module: "logos.wasm", capabilities: [],
                          sha256: String(repeating: "a", count: 64), hosts: output == "items" ? ["assets.example.com"] : nil, output: output,
                          permissions: permissions)
    }

    private func row(_ copy: String, permitted: Bool = true) throws -> ExtensionItem? {
        let output = #"{"items":[{"title":"Fictional logo","copy":"# + copy + "}]}"
        return try ExtensionNetwork.items(from: output, copyHosts: permitted ? hosts : nil).first
    }

    func testOnlyListExtensionsMayDeclareClipboardWrite() {
        XCTAssertNoThrow(try manifest().validate())
        XCTAssertTrue(manifest().wantsClipboardWrite)
        XCTAssertThrowsError(try manifest(output: nil).validate(), "A text extension has no rows to copy from")
        var json = manifest(output: nil); json.input = "json"
        XCTAssertThrowsError(try json.validate(), "JSON text extensions have no rows either")
        XCTAssertEqual(manifest().rowCopyHosts, hosts)
        XCTAssertNil(manifest(permissions: ["clipboard"]).rowCopyHosts)
    }

    func testClipboardWriteNeedsApprovalAgainOnUpdate() {
        let old = manifest(permissions: nil)
        XCTAssertFalse(manifest().requestsNoMoreThan(old), "Copying to the clipboard is new access")
        XCTAssertTrue(old.requestsNoMoreThan(manifest()))
        XCTAssertTrue(manifest().requestsNoMoreThan(manifest()))
    }

    func testCopyIsDroppedWithoutThePermission() throws {
        XCTAssertNil(try row(#"{"text":"<svg/>"}"#, permitted: false)?.copy)
        XCTAssertEqual(try row(#"{"text":"<svg/>"}"#)?.copy, ExtensionItemCopy(text: "<svg/>"))
        let reply = try ExtensionNetwork.reply(from: #"{"items":[{"title":"Logo","copy":{"text":"x"}}]}"#)
        XCTAssertNil(reply.items?.first?.copy, "A reply sanitized without copy hosts drops the copy")
    }

    func testTextCopiesAreBoundedAndNonEmpty() throws {
        let limit = String(repeating: "a", count: ExtensionItemCopy.maximumTextBytes)
        XCTAssertEqual(try row(#"{"text":"\#(limit)"}"#)?.copy?.text?.utf8.count, ExtensionItemCopy.maximumTextBytes)
        XCTAssertNil(try row(#"{"text":"\#(limit)a"}"#)?.copy, "Text over 64 KB is dropped, never cut")
        let multibyte = String(repeating: "é", count: ExtensionItemCopy.maximumTextBytes / 2 + 1)
        XCTAssertNil(try row(#"{"text":"\#(multibyte)"}"#)?.copy, "The limit counts UTF-8 bytes")
        XCTAssertNil(try row(#"{"text":""}"#)?.copy)
        XCTAssertNil(try row(#"{"text":"x","url":"https://assets.example.com/a.svg","type":"svg"}"#)?.copy, "A copy is text or a URL, not both")
        XCTAssertNil(try row("{}")?.copy)
    }

    func testURLCopiesNeedADeclaredHostAndAKnownType() throws {
        for type in ExtensionItemCopy.Kind.allCases.map(\.rawValue) {
            XCTAssertEqual(try row(#"{"url":"https://assets.example.com/logo","type":"\#(type)"}"#)?.copy?.kind?.rawValue, type)
        }
        XCTAssertEqual(ExtensionItemCopy.Kind.allCases.map(\.rawValue), ["svg", "png", "jpeg", "webp", "ico", "gif", "bmp", "avif", "image", "text"])
        XCTAssertNil(try row(#"{"url":"https://assets.example.com/logo.tif","type":"tiff"}"#)?.copy, "TIFF and HEIC come only through image")
        XCTAssertNil(try row(#"{"url":"https://assets.example.com/logo.heic","type":"heic"}"#)?.copy)
        XCTAssertNil(try row(#"{"url":"https://assets.example.com/logo","type":"IMAGE"}"#)?.copy, "Types are lowercase")
        XCTAssertNil(try row(#"{"url":"https://assets.example.com/logo.svg"}"#)?.copy, "A URL copy needs a type")
        XCTAssertNil(try row(#"{"url":"https://other.example.com/logo.svg","type":"svg"}"#)?.copy, "Undeclared host")
        XCTAssertNil(try row(#"{"url":"http://assets.example.com/logo.svg","type":"svg"}"#)?.copy, "Plain http")
        XCTAssertNil(try row(#"{"url":"https://assets.example.com:8443/logo.svg","type":"svg"}"#)?.copy, "Another port")
        XCTAssertNil(try row(#"{"url":"https://user@assets.example.com/logo.svg","type":"svg"}"#)?.copy, "Credentials")
        XCTAssertNil(try row(#"{"url":"file:///etc/hosts","type":"text"}"#)?.copy)
    }

    func testTitlesAreOneLineOfFortyCharacters() throws {
        XCTAssertEqual(try row(#"{"text":"x","title":"  Copy SVG  "}"#)?.copy?.title, "Copy SVG")
        XCTAssertEqual(try row(#"{"text":"x","title":"Copy\nSVG"}"#)?.copy?.title, "Copy SVG")
        XCTAssertEqual(try row(#"{"text":"x","title":"\#(String(repeating: "b", count: 60))"}"#)?.copy?.title?.count, 40)
        let untitled = try XCTUnwrap(try row(#"{"text":"x","title":"   "}"#)?.copy)
        XCTAssertNil(untitled.title)
        XCTAssertEqual(untitled.displayTitle, "Copy")
    }

    func testConfirmationsNameWhatWasCopied() {
        XCTAssertEqual(ExtensionItemCopy(text: "x", title: "Copy SVG").confirmation, "Copied SVG")
        XCTAssertEqual(ExtensionItemCopy(url: "https://assets.example.com/a", type: "svg").confirmation, "Copied SVG")
        XCTAssertEqual(ExtensionItemCopy(url: "https://assets.example.com/a", type: "png", title: "Logo").confirmation, "Copied image")
        XCTAssertEqual(ExtensionItemCopy(text: "x").confirmation, "Copied text")
    }

    func testDownloadedSVGMustBeUTF8Markup() {
        XCTAssertEqual(ExtensionItemCopy.downloadedText(Data(#"<svg xmlns="http://www.w3.org/2000/svg"/>"#.utf8), kind: .svg), #"<svg xmlns="http://www.w3.org/2000/svg"/>"#)
        XCTAssertEqual(ExtensionItemCopy.downloadedText(Data("\u{FEFF}\n  <?xml version=\"1.0\"?>\n<svg/>".utf8), kind: .svg),
                       "\n  <?xml version=\"1.0\"?>\n<svg/>", "The byte order mark is removed on every macOS version")
        XCTAssertEqual(ExtensionItemCopy.downloadedText(Data("\u{FEFF}notes".utf8), kind: .text), "notes")
        XCTAssertNil(ExtensionItemCopy.downloadedText(Data("<?xml version=\"1.0\"?><html/>".utf8), kind: .svg), "A prolog without an svg element")
        XCTAssertNil(ExtensionItemCopy.downloadedText(Data("<html><svg/></html>".utf8), kind: .svg))
        XCTAssertNil(ExtensionItemCopy.downloadedText(Data([0x89, 0x50, 0x4E, 0x47]), kind: .svg), "PNG bytes are not SVG")
        XCTAssertNil(ExtensionItemCopy.downloadedText(Data([0x3C, 0x73, 0x76, 0x67, 0xFF]), kind: .svg), "Invalid UTF-8")
        XCTAssertNil(ExtensionItemCopy.downloadedText(Data("<svg>\0</svg>".utf8), kind: .svg), "NUL characters")
        XCTAssertEqual(ExtensionItemCopy.downloadedText(Data("plain words".utf8), kind: .text), "plain words")
        XCTAssertNil(ExtensionItemCopy.downloadedText(Data(), kind: .text))
        XCTAssertNil(ExtensionItemCopy.downloadedText(Data("<svg/>".utf8), kind: .png), "Image kinds are never copied as text")
    }

    func testSVGMayStartWithAPrologDoctypeAndCommentsButItsRootMustBeSVG() {
        func svg(_ text: String) -> String? { ExtensionItemCopy.downloadedText(Data(text.utf8), kind: .svg) }
        let doctype = #"<!DOCTYPE svg PUBLIC "-//W3C//DTD SVG 1.1//EN" "http://www.w3.org/Graphics/SVG/1.1/DTD/svg11.dtd">"#
        let accepted = [
            doctype + #"<svg xmlns="http://www.w3.org/2000/svg"/>"#,
            "<!-- Generator: Fictional Draw 1.0 -->\n<svg viewBox=\"0 0 1 1\"></svg>",
            "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n<!-- a -->\n" + doctype + "\n<!-- b -->\n<svg>\n</svg>",
            "  \n\t<svg\nwidth=\"1\"/>",
            "<!DOCTYPE svg><svg/>"
        ]
        for text in accepted { XCTAssertEqual(svg(text), text, text) }
        let refused = [
            "<!DOCTYPE html><svg></svg>",
            "<!DOCTYPE html>\n<html><body><svg/></body></html>",
            #"<!DOCTYPE svg [ <!ENTITY a "aaaa"> ]><svg>&a;</svg>"#,
            "<!-- unterminated <svg/>",
            "<?xml version=\"1.0\"?><html><svg/></html>",
            "<svgx/>",
            "<svg",
            "<!-- a --><!DOCTYPE svg PUBLIC \"x\" \"y\"",
            String(repeating: "<!-- x -->", count: 17) + "<svg/>"
        ]
        for text in refused { XCTAssertNil(svg(text), text) }
    }

    func testImageSignaturesMatchTheirKind() {
        let png = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0, 0, 0, 0])
        let jpeg = Data([0xFF, 0xD8, 0xFF, 0xE0])
        let webp = Data("RIFF\0\0\0\0WEBPVP8 ".utf8)
        let ico = Data([0, 0, 1, 0, 1, 0])
        XCTAssertTrue(ExtensionItemCopy.hasImageSignature(png, kind: .png))
        XCTAssertTrue(ExtensionItemCopy.hasImageSignature(jpeg, kind: .jpeg))
        XCTAssertTrue(ExtensionItemCopy.hasImageSignature(webp, kind: .webp))
        XCTAssertTrue(ExtensionItemCopy.hasImageSignature(ico, kind: .ico))
        XCTAssertFalse(ExtensionItemCopy.hasImageSignature(jpeg, kind: .png))
        XCTAssertFalse(ExtensionItemCopy.hasImageSignature(png, kind: .webp))
        XCTAssertFalse(ExtensionItemCopy.hasImageSignature(Data("<svg/>".utf8), kind: .ico))
        XCTAssertFalse(ExtensionItemCopy.hasImageSignature(png, kind: .svg))
    }

    func testTheImageKindAcceptsEveryFormatWhileExplicitKindsStayStrict() {
        let samples: [(ExtensionImageFormat, Data)] = [
            (.png, Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0, 0, 0, 0])),
            (.jpeg, Data([0xFF, 0xD8, 0xFF, 0xE0])),
            (.gif, Data("GIF89a\u{1}\0\u{1}\0".utf8)),
            (.webp, Data("RIFF\0\0\0\0WEBPVP8 ".utf8)),
            (.ico, Data([0, 0, 1, 0, 2, 0])),
            (.bmp, Data("BM".utf8) + Data(repeating: 0, count: 12)),
            (.tiff, Data([0x49, 0x49, 0x2A, 0x00, 8, 0, 0, 0])),
            (.avif, Self.ftyp("avif", compatible: ["mif1", "miaf"])),
            (.heic, Self.ftyp("heic", compatible: ["mif1", "heic"]))
        ]
        let explicit: [ExtensionItemCopy.Kind: ExtensionImageFormat] = [.png: .png, .jpeg: .jpeg, .gif: .gif, .webp: .webp, .ico: .ico, .bmp: .bmp, .avif: .avif]
        for (format, data) in samples {
            XCTAssertEqual(ExtensionImageFormat.detect(data), format, format.rawValue)
            XCTAssertTrue(ExtensionItemCopy.hasImageSignature(data, kind: .image), format.rawValue)
            for (kind, accepted) in explicit {
                XCTAssertEqual(ExtensionItemCopy.hasImageSignature(data, kind: kind), accepted == format, "\(kind) with \(format)")
            }
            XCTAssertNil(ExtensionItemCopy.imageKindSVG(data), "Image bytes are never copied as SVG text")
        }
        XCTAssertEqual(ExtensionImageFormat.detect(Self.ftyp("mif1", compatible: ["avif"])), .avif, "AVIF named by a compatible brand")
        XCTAssertNil(ExtensionImageFormat.detect(Self.ftyp("isom", compatible: ["mp41"])), "An MP4 video is not an image")
        XCTAssertNil(ExtensionImageFormat.detect(Data([0, 0, 1, 0, 0, 0])), "An ICO header listing no images")
        XCTAssertNil(ExtensionImageFormat.detect(Data([0, 0, 2, 0, 1, 0])), "A cursor file")
        XCTAssertNil(ExtensionImageFormat.detect(Data("%PDF-1.7".utf8)))
        XCTAssertNil(ExtensionImageFormat.detect(Data()))
        XCTAssertFalse(ExtensionItemCopy.hasImageSignature(Data("<svg/>".utf8), kind: .image))
        XCTAssertEqual(ExtensionItemCopy.imageKindSVG(Data("\u{FEFF}<svg xmlns=\"http://www.w3.org/2000/svg\"/>".utf8)), "<svg xmlns=\"http://www.w3.org/2000/svg\"/>",
                       "An image copy that is SVG markup is copied as text")
        XCTAssertNil(ExtensionItemCopy.imageKindSVG(Data("<html/>".utf8)))
        XCTAssertEqual(ExtensionItemCopy.Kind.image.displayName, "image")
        XCTAssertEqual(ExtensionItemCopy(url: "https://assets.example.com/a", type: "image").confirmation, "Copied image")
    }

    /// An ISO base media `ftyp` box with a major brand and compatible brands, as AVIF and HEIC files start.
    static func ftyp(_ major: String, compatible: [String]) -> Data {
        let size = 16 + 4 * compatible.count
        return Data([0, 0, 0, UInt8(size)]) + Data("ftyp\(major)".utf8) + Data([0, 0, 0, 0]) + Data(compatible.joined().utf8)
    }

    func testErrorsExplainWhyNothingWasCopied() {
        XCTAssertEqual(ExtensionCopyError.hostNotApproved("assets.example.com").errorDescription, "Allow access to assets.example.com to copy this.")
        XCTAssertEqual(ExtensionCopyError.wrongType(.png).errorDescription, "The download isn’t a valid PNG image, so nothing was copied.")
        XCTAssertEqual(ExtensionCopyError.unavailable(404).errorDescription, "Couldn’t download it: the server answered 404. Nothing was copied.")
        XCTAssertEqual(ExtensionCopyError.tooLarge.errorDescription, "It’s larger than 512 KB, so nothing was copied.")
    }
}
