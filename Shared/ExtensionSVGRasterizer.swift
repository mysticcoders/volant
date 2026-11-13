import AppKit
import VolantCore

/// Draws an SVG row image preview, in VolantExtensionHost only: the sandboxed helper with no network
/// access. The markup is checked again here (`ExtensionSVGPreview.sanitized`), then drawn with AppKit's
/// own SVG image representation (CoreSVG, the renderer behind SVG in asset catalogs, not a browser engine)
/// into the same fresh 8-bit sRGB bitmap a raster preview is redrawn into
/// (`ExtensionImageDecoding.redrawnPNG`), so the renderer's own bitmap never leaves this process. The app
/// target leaves this file out; Volant never draws extension SVG itself.
enum ExtensionSVGRasterizer {
    /// How a preview ended. The refusal and the other outcomes travel to the app as short codes.
    enum Outcome: Equatable {
        case png(Data)
        case refused(ExtensionSVGPreview.Refusal)
        case unavailable, failed

        /// The code the helper replies with for anything but a PNG.
        var code: String {
            switch self {
            case .png: "png"
            case .refused(let refusal): "refused." + refusal.rawValue
            case .unavailable: "unavailable"
            case .failed: "failed"
            }
        }
    }

    static let svgType = "public.svg-image"

    /// The image representation class AppKit registers for SVG, or nil on a macOS that has none.
    static var representationClass: AnyClass? { NSImageRep.class(forType: svgType) }

    /// A PNG of the SVG in `data`, at most `maximumPixels` on its longer side, when the markup passes the
    /// check and AppKit's SVG representation, and only it, opens it at a size within the check's bounds.
    static func rasterize(_ data: Data, maximumPixels: Int = ExtensionItemImage.thumbnailPixels) -> Outcome {
        switch ExtensionSVGPreview.sanitized(data) {
        case .failure(let refusal): return .refused(refusal)
        case .success(let markup): return draw(markup, maximumPixels: maximumPixels)
        }
    }

    /// Draws markup without checking it first. Only `rasterize` calls this outside tests; the tests use it
    /// to confirm the renderer itself fetches nothing even when the check is bypassed.
    static func draw(_ markup: Data, maximumPixels: Int) -> Outcome {
        guard let svgClass = representationClass else { return .unavailable }
        guard (1...ExtensionItemImage.thumbnailPixels).contains(maximumPixels), let image = NSImage(data: markup),
              image.representations.count == 1, let representation = image.representations.first,
              ObjectIdentifier(type(of: representation)) == ObjectIdentifier(svgClass) else { return .failed }
        image.cacheMode = .never
        let size = image.size
        guard size.width.isFinite, size.height.isFinite, size.width > 0, size.height > 0,
              size.width <= ExtensionSVGPreview.maximumDimension, size.height <= ExtensionSVGPreview.maximumDimension else { return .failed }
        let (width, height) = ExtensionImageDecoding.fitted(width: Double(size.width), height: Double(size.height), maximumPixels: maximumPixels)
        let png = ExtensionImageDecoding.redrawnPNG(width: width, height: height) { context in
            NSGraphicsContext.saveGraphicsState()
            defer { NSGraphicsContext.restoreGraphicsState() }
            NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
            image.draw(in: NSRect(x: 0, y: 0, width: width, height: height), from: .zero, operation: .sourceOver, fraction: 1)
        }
        return png.map(Outcome.png) ?? .failed
    }
}
