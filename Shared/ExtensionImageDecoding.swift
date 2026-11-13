import Foundation
import ImageIO
import VolantCore

/// Opens downloaded extension images with ImageIO only after their signature names a format Volant
/// accepts, and only when ImageIO agrees, so a download never reaches a decoder for another format. Used
/// by the fetch helper to draw row image thumbnails, and by the app for a row's copy, which the owner
/// chose. Nothing is cached, and a source past the size bounds is refused before any pixel is decoded.
enum ExtensionImageDecoding {
    /// An opened image: its source, the frame to use and that frame's pixel size.
    struct Opened {
        let source: CGImageSource
        let index: Int
        let width: Int
        let height: Int
    }

    private static let noCache = [kCGImageSourceShouldCache: false] as CFDictionary

    /// The image in `data` when its signature is one of `formats`, ImageIO reports that format, and the
    /// chosen frame is at most `maximumDimension` pixels on a side and `maximumPixels` in all. The frame
    /// is the first, or for an ICO the largest entry, since favicons often list 16 pixels first.
    static func open(_ data: Data, accepting formats: Set<ExtensionImageFormat>,
                     maximumDimension: Int = ExtensionItemImage.maximumSourceDimension,
                     maximumPixels: Int = ExtensionItemImage.maximumSourcePixels) -> Opened? {
        guard let format = ExtensionImageFormat.detect(data), formats.contains(format),
              let source = CGImageSourceCreateWithData(data as CFData, noCache),
              let type = CGImageSourceGetType(source) as String?, format.typeIdentifiers.contains(type) else { return nil }
        let count = CGImageSourceGetCount(source)
        guard count > 0 else { return nil }
        let candidates = format == .ico ? Array(0..<min(count, 64)) : [format == .heic ? CGImageSourceGetPrimaryImageIndex(source) : 0]
        var best: Opened?
        for index in candidates {
            guard let properties = CGImageSourceCopyPropertiesAtIndex(source, index, noCache) as? [CFString: Any],
                  let width = properties[kCGImagePropertyPixelWidth] as? Int, let height = properties[kCGImagePropertyPixelHeight] as? Int,
                  (1...maximumDimension).contains(width), (1...maximumDimension).contains(height), width * height <= maximumPixels else { continue }
            if best.map({ width * height > $0.width * $0.height }) ?? true { best = Opened(source: source, index: index, width: width, height: height) }
        }
        return best
    }

    /// A PNG thumbnail of the image in `data`, at most `maximumPixels` on its longer side, redrawn into a
    /// fresh 8-bit sRGB bitmap so no metadata, color profile or animation from the download survives.
    /// Nil when the bytes are not an accepted raster image (SVG included), exceed the bounds, fail to
    /// decode, or the PNG would be larger than `ExtensionItemImage.maximumThumbnailBytes`.
    static func thumbnailPNG(_ data: Data, maximumPixels: Int = ExtensionItemImage.thumbnailPixels) -> Data? {
        guard let opened = open(data, accepting: Set(ExtensionImageFormat.allCases)) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maximumPixels,
            kCGImageSourceShouldCache: false,
            kCGImageSourceShouldCacheImmediately: false
        ]
        guard let thumbnail = CGImageSourceCreateThumbnailAtIndex(opened.source, opened.index, options as CFDictionary) else { return nil }
        let (width, height) = fitted(width: Double(thumbnail.width), height: Double(thumbnail.height), maximumPixels: maximumPixels)
        return redrawnPNG(width: width, height: height) { context in
            context.draw(thumbnail, in: CGRect(x: 0, y: 0, width: width, height: height))
        }
    }

    /// The pixel size of a `width` by `height` image scaled down, never up, to fit `maximumPixels` on its
    /// longer side, at least 1 by 1.
    static func fitted(width: Double, height: Double, maximumPixels: Int) -> (width: Int, height: Int) {
        let scale = min(1, Double(maximumPixels) / max(width, height))
        return (max(1, Int((width * scale).rounded())), max(1, Int((height * scale).rounded())))
    }

    /// A PNG of what `draw` paints into a fresh, cleared `width` by `height` 8-bit sRGB bitmap with
    /// premultiplied alpha, so nothing from the source survives except its pixels. Nil when the bitmap
    /// cannot be made or the PNG would be larger than `ExtensionItemImage.maximumThumbnailBytes`.
    static func redrawnPNG(width: Int, height: Int, draw: (CGContext) -> Void) -> Data? {
        guard (1...ExtensionItemImage.thumbnailPixels).contains(width), (1...ExtensionItemImage.thumbnailPixels).contains(height),
              let space = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0, space: space,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        context.clear(CGRect(x: 0, y: 0, width: width, height: height))
        context.interpolationQuality = .high
        draw(context)
        guard let redrawn = context.makeImage() else { return nil }
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(output, "public.png" as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(destination, redrawn, nil)
        guard CGImageDestinationFinalize(destination), output.length <= ExtensionItemImage.maximumThumbnailBytes else { return nil }
        return output as Data
    }
}
