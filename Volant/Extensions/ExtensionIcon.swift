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
              let data = try? Data(contentsOf: url), data.count <= ExtensionManifest.maximumIconBytes,
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
