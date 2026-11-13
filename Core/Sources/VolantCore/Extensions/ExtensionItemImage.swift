import Foundation

/// A picture a list extension's row shows at its leading edge in place of the extension's icon, such as
/// a site's favicon or a company's logo, for an extension whose manifest declares the `row-images`
/// permission. `url` must be https on the default port to a host the manifest declares; anything else is
/// dropped while sanitizing and the row keeps its symbol or the extension's icon.
///
/// Volant fetches it only while the row is on screen, through its fetch helper, from a host the owner
/// allowed, at most `maximumDownloadBytes`. The helper decodes the download and returns a PNG thumbnail
/// of at most `thumbnailPixels` on a side that it drew itself; the app decodes only that PNG. SVG is
/// checked (`ExtensionSVGPreview`) and drawn into the same kind of PNG by the extension helper, which has
/// no network access, never by the app; refused SVG shows the placeholder. Thumbnails stay in memory for
/// the session and are never written to disk.
public struct ExtensionItemImage: Codable, Hashable, Sendable {
    public static let permission = "row-images"
    /// The largest download a row image accepts.
    public static let maximumDownloadBytes = 256 * 1024
    /// The longest side of the thumbnail the fetch helper returns, twice the row's 24 points, rounded up.
    public static let thumbnailPixels = 64
    /// The largest thumbnail the app accepts from the helper. A 64 by 64 RGBA PNG is at most about 17 KB.
    public static let maximumThumbnailBytes = 64 * 1024
    /// Fetches running at once, across every list.
    public static let maximumConcurrentFetches = 4
    /// Fetches one list may start; rows past this show the placeholder.
    public static let maximumFetchesPerList = 30
    /// The session cache's bounds, counted by entry and by decoded pixel bytes.
    public static let maximumCachedImages = 200
    public static let maximumCachedBytes = 4 * 1024 * 1024
    /// The largest source image the helper decodes for a preview, half a copied image's bounds, since a
    /// preview loads without the owner choosing it and a small file can describe a huge bitmap.
    public static let maximumSourceDimension = 4096
    public static let maximumSourcePixels = 16_000_000

    public var url: String

    public init(url: String) { self.url = url }

    /// The image as Volant keeps it, or nil to drop it: a URL permitted for `hosts`, the manifest's
    /// declared hosts. Whether the owner allowed the host is checked again before every fetch.
    public func sanitized(hosts: Set<String>) -> ExtensionItemImage? {
        ExtensionNetwork.permittedURL(url, hosts: hosts) == nil ? nil : self
    }

    /// Whether `data` is a PNG within the thumbnail's byte limit, by signature. The app also decodes it
    /// with ImageIO and checks its pixel size before showing it.
    public static func looksLikeThumbnail(_ data: Data) -> Bool {
        data.count <= maximumThumbnailBytes && ExtensionImageFormat.detect(data) == .png
    }
}

extension ExtensionManifest {
    public var wantsRowImages: Bool { declaredPermissions.contains(ExtensionItemImage.permission) }

    /// The hosts a row's `image` may load from, or nil when the manifest does not declare `row-images`,
    /// so every row's image is dropped while sanitizing.
    public var rowImageHosts: Set<String>? { wantsRowImages ? Set(declaredHosts) : nil }
}
