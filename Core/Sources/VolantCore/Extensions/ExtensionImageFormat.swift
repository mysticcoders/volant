import Foundation

/// The raster image formats Volant decodes for extensions: a row's copy and a row's image preview.
/// Downloaded bytes are identified by their signature here, before ImageIO sees them, and ImageIO must
/// then report one of the format's type identifiers, so a download can never reach a decoder for a
/// format outside this list (such as PDF, PSD or camera raw). SVG is not here: ImageIO never sees it, and
/// row previews draw it only in the extension helper (`ExtensionSVGPreview`).
public enum ExtensionImageFormat: String, CaseIterable, Sendable {
    case png, jpeg, gif, webp, ico, bmp, tiff, avif, heic

    /// The Uniform Type Identifiers ImageIO may report for a decoded image of this format. HEIF files
    /// read as `public.heic` or `public.heif` depending on their brand.
    public var typeIdentifiers: Set<String> {
        switch self {
        case .png: ["public.png"]
        case .jpeg: ["public.jpeg"]
        case .gif: ["com.compuserve.gif"]
        case .webp: ["org.webmproject.webp"]
        case .ico: ["com.microsoft.ico"]
        case .bmp: ["com.microsoft.bmp"]
        case .tiff: ["public.tiff"]
        case .avif: ["public.avif"]
        case .heic: ["public.heic", "public.heif"]
        }
    }

    /// The format whose signature `data` starts with, or nil. AVIF and HEIC share the ISO base media
    /// `ftyp` box and are told apart by its major and compatible brands.
    public static func detect(_ data: Data) -> ExtensionImageFormat? {
        let bytes = [UInt8](data.prefix(64))
        if bytes.starts(with: [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]) { return .png }
        if bytes.starts(with: [0xFF, 0xD8, 0xFF]) { return .jpeg }
        if bytes.starts(with: Array("GIF87a".utf8)) || bytes.starts(with: Array("GIF89a".utf8)) { return .gif }
        if ExtensionManifest.looksLikeWebP(data) { return .webp }
        if bytes.count >= 6, bytes.starts(with: [0x00, 0x00, 0x01, 0x00]), bytes[4] != 0 || bytes[5] != 0 { return .ico }
        if bytes.count >= 14, bytes.starts(with: Array("BM".utf8)) { return .bmp }
        if bytes.starts(with: [0x49, 0x49, 0x2A, 0x00]) || bytes.starts(with: [0x4D, 0x4D, 0x00, 0x2A]) { return .tiff }
        return isoBrandFormat(bytes)
    }

    /// AVIF or HEIC from an `ftyp` box at the start of the file: its size, `ftyp`, the major brand, a
    /// minor version, then compatible brands. Nil for any other ISO media file, such as a video.
    static func isoBrandFormat(_ bytes: [UInt8]) -> ExtensionImageFormat? {
        guard bytes.count >= 16, bytes[4..<8].elementsEqual(Array("ftyp".utf8)) else { return nil }
        let size = Int(bytes[0]) << 24 | Int(bytes[1]) << 16 | Int(bytes[2]) << 8 | Int(bytes[3])
        guard size >= 16, size % 4 == 0 else { return nil }
        let end = min(size, bytes.count)
        var brands = [String(decoding: bytes[8..<12], as: UTF8.self)]
        var offset = 16
        while offset + 4 <= end {
            brands.append(String(decoding: bytes[offset..<offset + 4], as: UTF8.self)); offset += 4
        }
        if brands.contains(where: { ["avif", "avis"].contains($0) }) { return .avif }
        if brands.contains(where: { ["heic", "heix", "heim", "heis", "mif1", "msf1"].contains($0) }) { return .heic }
        return nil
    }
}
