import AppKit
import ImageIO
import VolantCore

/// What an extension row's copy puts on the clipboard: plain text, or an image as PNG and TIFF data so
/// apps that read either can paste it. Downloaded bytes become content only after they prove to be the
/// declared kind; SVG is checked as text and never parsed or rendered.
enum ExtensionCopyContent: Equatable {
    case text(String)
    case image(png: Data, tiff: Data)

    /// The largest image Volant decodes for a copy, so a small file cannot expand into a huge bitmap.
    static let maximumImageDimension = 8192
    static let maximumImagePixels = 32_000_000

    /// Content for downloaded bytes of `kind`, or nil when they are not that kind: SVG and text must pass
    /// `ExtensionItemCopy.downloadedText`; an image must carry the signature of a format the kind accepts,
    /// be reported by ImageIO as that format, stay within the size limits, and decode. An `image` copy
    /// that is SVG markup instead is copied as text, like `svg`. A GIF copies its first frame and an ICO
    /// its largest entry.
    init?(_ data: Data, kind: ExtensionItemCopy.Kind) {
        guard kind.isImage else {
            guard let text = ExtensionItemCopy.downloadedText(data, kind: kind) else { return nil }
            self = .text(text); return
        }
        if kind == .image, let svg = ExtensionItemCopy.imageKindSVG(data) { self = .text(svg); return }
        guard ExtensionItemCopy.hasImageSignature(data, kind: kind),
              let opened = ExtensionImageDecoding.open(data, accepting: kind.formats, maximumDimension: Self.maximumImageDimension,
                                                       maximumPixels: Self.maximumImagePixels),
              let image = CGImageSourceCreateImageAtIndex(opened.source, opened.index, [kCGImageSourceShouldCache: false] as CFDictionary) else { return nil }
        let bitmap = NSBitmapImageRep(cgImage: image)
        guard let png = bitmap.representation(using: .png, properties: [:]), let tiff = bitmap.tiffRepresentation else { return nil }
        self = .image(png: png, tiff: tiff)
    }

    /// Replaces the clipboard's contents with this content.
    func write(to pasteboard: NSPasteboard) {
        pasteboard.clearContents()
        switch self {
        case .text(let text): pasteboard.setString(text, forType: .string)
        case .image(let png, let tiff):
            pasteboard.declareTypes([.png, .tiff], owner: nil)
            pasteboard.setData(png, forType: .png)
            pasteboard.setData(tiff, forType: .tiff)
        }
    }
}
