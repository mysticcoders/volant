import ImageIO
import UniformTypeIdentifiers
import XCTest

/// Fictional test images of every format extension rows copy or preview, generated in memory: solid
/// colors, an animated GIF whose frames differ, and ICO files built by hand with PNG and BMP entries,
/// since ImageIO's ICO writer picks the entry format itself.
enum ExtensionImageFixtures {
    struct Color { var red: UInt8, green: UInt8, blue: UInt8 }
    static let blue = Color(red: 30, green: 90, blue: 220)
    static let red = Color(red: 220, green: 40, blue: 30)
    static let green = Color(red: 40, green: 180, blue: 60)

    /// A fictional solid-color lossless WebP, the one the launcher fixtures use as an icon. ImageIO reads
    /// WebP but cannot write it, so it is a fixture.
    static let webp = Data(base64Encoded: "UklGRh4AAABXRUJQVlA4TBEAAAAvH8AHAAdQvKIUuf+BiOh/AAA=")!

    /// A solid image of `color`.
    static func cgImage(width: Int, height: Int, _ color: Color) -> CGImage {
        let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.setFillColor(red: CGFloat(color.red) / 255, green: CGFloat(color.green) / 255, blue: CGFloat(color.blue) / 255, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        return context.makeImage()!
    }

    /// `images` encoded as `type` by ImageIO, or nil when this macOS cannot write that type.
    static func encoded(_ type: UTType, _ images: [CGImage], properties: [CFString: Any]? = nil) -> Data? {
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, type.identifier as CFString, images.count, nil) else { return nil }
        for image in images { CGImageDestinationAddImage(destination, image, properties as CFDictionary?) }
        return CGImageDestinationFinalize(destination) ? data as Data : nil
    }

    static func image(_ type: UTType, width: Int = 16, height: Int = 16, _ color: Color = blue) -> Data? {
        encoded(type, [cgImage(width: width, height: height, color)])
    }

    /// A two-frame GIF whose first frame is `first` and second `second`.
    static func animatedGIF(first: Color, second: Color) -> Data {
        let frame = [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFDelayTime: 0.1]]
        return encoded(.gif, [cgImage(width: 16, height: 16, first), cgImage(width: 16, height: 16, second)], properties: frame)!
    }

    /// One entry of a hand-built ICO: its pixel size and image bytes.
    struct IcoEntry { var size: Int; var bytes: Data }

    static func icoPNGEntry(size: Int, _ color: Color) -> IcoEntry {
        IcoEntry(size: size, bytes: encoded(.png, [cgImage(width: size, height: size, color)])!)
    }

    /// A 32-bit BMP entry: a BITMAPINFOHEADER of double height, bottom-up BGRA pixels, then an opaque AND mask.
    static func icoBMPEntry(size: Int, _ color: Color) -> IcoEntry {
        var data = Data()
        func le32(_ value: Int) { withUnsafeBytes(of: UInt32(truncatingIfNeeded: value).littleEndian) { data.append(contentsOf: $0) } }
        func le16(_ value: Int) { withUnsafeBytes(of: UInt16(truncatingIfNeeded: value).littleEndian) { data.append(contentsOf: $0) } }
        le32(40); le32(size); le32(size * 2); le16(1); le16(32); le32(0); le32(size * size * 4); le32(0); le32(0); le32(0); le32(0)
        for _ in 0..<(size * size) { data.append(contentsOf: [color.blue, color.green, color.red, 255]) }
        let maskRow = ((size + 31) / 32) * 4
        data.append(Data(repeating: 0, count: maskRow * size))
        return IcoEntry(size: size, bytes: data)
    }

    /// An ICO file listing `entries` in order.
    static func ico(_ entries: [IcoEntry]) -> Data {
        var data = Data([0, 0, 1, 0, UInt8(entries.count), 0])
        var offset = 6 + 16 * entries.count
        for entry in entries {
            let side = UInt8(entry.size >= 256 ? 0 : entry.size)
            data.append(contentsOf: [side, side, 0, 0, 1, 0, 32, 0])
            withUnsafeBytes(of: UInt32(entry.bytes.count).littleEndian) { data.append(contentsOf: $0) }
            withUnsafeBytes(of: UInt32(offset).littleEndian) { data.append(contentsOf: $0) }
            offset += entry.bytes.count
        }
        for entry in entries { data.append(entry.bytes) }
        return data
    }

    /// The pixel size and center color of PNG or other image bytes, decoded by ImageIO.
    static func inspect(_ data: Data) -> (width: Int, height: Int, center: Color)? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil), let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { return nil }
        var pixel = [UInt8](repeating: 0, count: 4)
        guard let context = CGContext(data: &pixel, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
                                      space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        context.interpolationQuality = .none
        context.draw(image, in: CGRect(x: -CGFloat(image.width) / 2 + 0.5, y: -CGFloat(image.height) / 2 + 0.5, width: CGFloat(image.width), height: CGFloat(image.height)))
        return (image.width, image.height, Color(red: pixel[0], green: pixel[1], blue: pixel[2]))
    }

    /// Whether two colors match within the rounding a color conversion may add.
    static func close(_ first: Color, _ second: Color, tolerance: Int = 12) -> Bool {
        abs(Int(first.red) - Int(second.red)) <= tolerance && abs(Int(first.green) - Int(second.green)) <= tolerance &&
            abs(Int(first.blue) - Int(second.blue)) <= tolerance
    }
}
