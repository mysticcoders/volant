import XCTest

@testable import VolantCore

/// The `row-images` permission and a row's `image`: who may declare it, how sanitizing keeps or drops it,
/// the limits Volant enforces, and the PNG check for the fetch helper's thumbnails.
final class ExtensionItemImageTests: XCTestCase {
    private let hosts: Set<String> = ["icons.example.com"]

    private func manifest(output: String? = "items", permissions: [String]? = ["row-images"]) -> ExtensionManifest {
        ExtensionManifest(id: "community.fictional.favicons", name: "Fictional Favicons", version: "1", module: "favicons.wasm", capabilities: [],
                          sha256: String(repeating: "a", count: 64), hosts: output == "items" ? ["icons.example.com"] : nil, output: output,
                          permissions: permissions)
    }

    private func row(_ image: String, permitted: Bool = true) throws -> ExtensionItem? {
        let output = #"{"items":[{"title":"Fictional site","url":"https://site.example.com","image":"# + image + "}]}"
        return try ExtensionNetwork.items(from: output, imageHosts: permitted ? hosts : nil).first
    }

    func testOnlyListExtensionsMayDeclareRowImages() {
        XCTAssertNoThrow(try manifest().validate())
        XCTAssertTrue(manifest().wantsRowImages)
        XCTAssertTrue(ExtensionManifest.knownPermissions.contains("row-images"))
        XCTAssertThrowsError(try manifest(output: nil).validate(), "A text extension has no rows")
        var json = manifest(output: nil); json.input = "json"
        XCTAssertThrowsError(try json.validate(), "JSON text extensions have no rows either")
        XCTAssertEqual(manifest().rowImageHosts, hosts)
        XCTAssertNil(manifest(permissions: ["clipboard-write"]).rowImageHosts)
        XCTAssertNoThrow(try manifest(permissions: ["clipboard-write", "row-images"]).validate())
        XCTAssertThrowsError(try manifest(permissions: ["row-images", "row-images"]).validate(), "No duplicates")
    }

    func testRowImagesNeedApprovalAgainOnUpdate() {
        let old = manifest(permissions: nil)
        XCTAssertFalse(manifest().requestsNoMoreThan(old), "Showing images from its sites is new access")
        XCTAssertTrue(old.requestsNoMoreThan(manifest()))
    }

    func testImageIsDroppedWithoutThePermission() throws {
        let image = #"{"url":"https://icons.example.com/site.ico"}"#
        XCTAssertNil(try row(image, permitted: false)?.image)
        XCTAssertEqual(try row(image)?.image, ExtensionItemImage(url: "https://icons.example.com/site.ico"))
        XCTAssertEqual(try row(image, permitted: false)?.title, "Fictional site", "The row stays")
        let reply = try ExtensionNetwork.reply(from: #"{"items":[{"title":"Site","image":{"url":"https://icons.example.com/a.png"}}]}"#)
        XCTAssertNil(reply.items?.first?.image, "A reply sanitized without image hosts drops the image")
        let sanitized = try ExtensionNetwork.reply(from: #"{"items":[{"title":"Site","image":{"url":"https://icons.example.com/a.png"}}]}"#, for: manifest())
        XCTAssertNotNil(sanitized.items?.first?.image, "A reply sanitized for a manifest with row-images keeps it")
    }

    func testImageURLsFollowThePlanRules() throws {
        XCTAssertNotNil(try row(#"{"url":"https://icons.example.com/ip3/site.example.com.ico"}"#)?.image)
        XCTAssertNotNil(try row(#"{"url":"https://icons.example.com:443/a.png"}"#)?.image, "The default port")
        XCTAssertNil(try row(#"{"url":"https://other.example.com/a.png"}"#)?.image, "Undeclared host")
        XCTAssertNil(try row(#"{"url":"http://icons.example.com/a.png"}"#)?.image, "Plain http")
        XCTAssertNil(try row(#"{"url":"https://icons.example.com:8443/a.png"}"#)?.image, "Another port")
        XCTAssertNil(try row(#"{"url":"https://user:pass@icons.example.com/a.png"}"#)?.image, "Credentials")
        XCTAssertNil(try row(#"{"url":"https://icons.example.com/a.png#frag"}"#)?.image, "Fragment")
        XCTAssertNil(try row(#"{"url":"data:image/png;base64,AAAA"}"#)?.image, "Inline data")
        XCTAssertNil(try row(#"{"url":"file:///Users/owner/a.png"}"#)?.image)
        let long = "https://icons.example.com/" + String(repeating: "a", count: ExtensionNetwork.maximumURLLength)
        XCTAssertNil(try row(#"{"url":"\#(long)"}"#)?.image, "Over the URL length limit")
        XCTAssertThrowsError(try row(#""https://icons.example.com/a.png""#), "An image must be an object, like every other row field's shape")
    }

    func testOlderShapesAndUnknownFieldsStillDecode() throws {
        let rows = try ExtensionNetwork.items(from: #"{"items":[{"title":"Site","image":{"url":"https://icons.example.com/a.png","size":"large"}},{"title":"Plain"}]}"#,
                                              imageHosts: hosts)
        XCTAssertEqual(rows.map(\.title), ["Site", "Plain"])
        XCTAssertNotNil(rows[0].image)
        XCTAssertNil(rows[1].image)
    }

    func testLimitsAreBounded() {
        XCTAssertEqual(ExtensionItemImage.maximumDownloadBytes, 256 * 1024)
        XCTAssertEqual(ExtensionItemImage.thumbnailPixels, 64)
        XCTAssertEqual(ExtensionItemImage.maximumConcurrentFetches, 4)
        XCTAssertEqual(ExtensionItemImage.maximumFetchesPerList, 30)
        XCTAssertEqual(ExtensionItemImage.maximumCachedImages, 200)
        XCTAssertLessThanOrEqual(ExtensionItemImage.maximumDownloadBytes, ExtensionNetwork.maximumResponseBytes)
        XCTAssertLessThanOrEqual(ExtensionItemImage.maximumSourceDimension * ExtensionItemImage.maximumSourceDimension / 4, ExtensionItemImage.maximumSourcePixels)
    }

    func testThumbnailsMustBeSmallPNGs() {
        let png = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]) + Data(repeating: 0, count: 100)
        XCTAssertTrue(ExtensionItemImage.looksLikeThumbnail(png))
        XCTAssertFalse(ExtensionItemImage.looksLikeThumbnail(png + Data(repeating: 0, count: ExtensionItemImage.maximumThumbnailBytes)), "Too large")
        XCTAssertFalse(ExtensionItemImage.looksLikeThumbnail(Data([0xFF, 0xD8, 0xFF, 0xE0])), "JPEG")
        XCTAssertFalse(ExtensionItemImage.looksLikeThumbnail(Data("<svg/>".utf8)))
        XCTAssertFalse(ExtensionItemImage.looksLikeThumbnail(Data()))
    }
}
