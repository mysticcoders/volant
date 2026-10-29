import AppKit
import ImageIO
import VolantCore

/// Loads an extension's optional icon: a square WebP named in its manifest and pinned by SHA-256.
/// The file must sit in the extension's own folder, be at most 32 KB, match its hash, be a WebP that
/// ImageIO reads as such, and be square between 16 and 512 pixels; anything else falls back to the
/// row's symbol. Results, including failures, are cached by folder and hash, so rows never reread
/// the file while scrolling.
enum ExtensionIcon {
    private static var cache: [String: NSImage?] = [:]

    static func image(for ext: InstalledExtension) -> NSImage? {
        guard let name = ext.manifest.icon, let hash = ext.manifest.iconSha256 else { return nil }
        let key = ext.directory.path + "\u{0}" + hash
        if let cached = cache[key] { return cached }
        let image = load(ext.directory.appendingPathComponent(name), in: ext.directory, sha256: hash)
        cache[key] = image
        return image
    }

    /// Reads and checks one icon file; nil when any check fails.
    static func load(_ url: URL, in directory: URL, sha256: String) -> NSImage? {
        guard ExtensionManager.sameLocation(url.resolvingSymlinksInPath().deletingLastPathComponent(), directory),
              let size = (try? FileManager.default.attributesOfItem(atPath: url.path))?[.size] as? Int, size <= ExtensionManifest.maximumIconBytes,
              let data = try? Data(contentsOf: url) else { return nil }
        return decode(data, sha256: sha256)
    }

    /// Checks icon bytes against their pinned SHA-256 and decodes them: a square WebP of 16 to 512
    /// pixels and at most 32 KB. Nil when any check fails.
    static func decode(_ data: Data, sha256: String) -> NSImage? {
        guard data.count <= ExtensionManifest.maximumIconBytes,
              ExtensionManifest.looksLikeWebP(data), Integrity.sha256(data) == sha256,
              let source = CGImageSourceCreateWithData(data as CFData, [kCGImageSourceTypeIdentifierHint: "org.webmproject.webp"] as CFDictionary),
              CGImageSourceGetType(source) as String? == "org.webmproject.webp", CGImageSourceGetCount(source) == 1,
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int, let height = properties[kCGImagePropertyPixelHeight] as? Int,
              width == height, (16...512).contains(width),
              let image = CGImageSourceCreateImageAtIndex(source, 0, [kCGImageSourceShouldCacheImmediately: true] as CFDictionary) else {
            return nil
        }
        return NSImage(cgImage: image, size: NSSize(width: 32, height: 32))
    }
}

/// Icons for catalog listings that aren't installed, fetched from the signed catalog only after the
/// owner loaded it (Check for Updates, Browse Extensions or the launcher's Extension Catalog). Each
/// is fetched once through the fetch helper's fixed catalog paths, must match the SHA-256 the signed
/// index lists, and passes the same checks as an installed icon. Results, including failures, are kept
/// in memory for the session by hash, so a listing whose icon failed shows the symbol.
final class ExtensionCatalogIcons: ObservableObject {
    static let shared = ExtensionCatalogIcons()
    @Published private(set) var images: [String: NSImage] = [:]
    private var requested: Set<String> = []

    func image(for listing: ExtensionCatalog.Listing) -> NSImage? {
        listing.iconFile.flatMap { images[$0.sha256] }
    }

    /// Fetches the icons of `listings` not fetched yet this session.
    func fetch(_ listings: [ExtensionCatalog.Listing], using client: ExtensionCatalogClient) {
        for listing in listings {
            guard let path = listing.iconPath, let file = listing.iconFile, requested.insert(file.sha256).inserted else { continue }
            client.fetchFile(path, file.size) { [weak self] result in
                guard let data = try? result.get(), let image = ExtensionIcon.decode(data, sha256: file.sha256) else { return }
                DispatchQueue.main.async { self?.images[file.sha256] = image }
            }
        }
    }
}
