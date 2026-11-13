import AppKit

/// App Store creative assets for Volant Mobile, drawn from raw simulator screenshots:
///   header.png  21:9 at 3840x1646: the wing and wordmark with a tagline, three screens fanned to the right.
///   search.png  3:2 at 3840x2560: three screens side by side, no text, since search results show the name.
///
///   swift creative.swift <raw-screenshot-dir> <out-dir>
let arguments = CommandLine.arguments
guard arguments.count == 3 else {
    FileHandle.standardError.write(Data("usage: creative.swift <raw-screenshot-dir> <out-dir>\n".utf8))
    exit(2)
}
let raw = URL(fileURLWithPath: arguments[1]), out = URL(fileURLWithPath: arguments[2])
let space = CGColorSpace(name: CGColorSpace.sRGB)!

/// sRGB color from 0–255 components.
func rgb(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: r / 255, green: g / 255, blue: b / 255, alpha: a)
}

func screenshot(_ name: String) -> CGImage {
    guard let image = NSImage(contentsOf: raw.appendingPathComponent(name))?.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
        FileHandle.standardError.write(Data("missing \(name) in \(raw.path)\n".utf8))
        exit(1)
    }
    return image
}

/// An opaque canvas with Volant's near-black background and a rust-to-amber glow around `glowAt`.
func canvas(_ width: Int, _ height: Int, glowAt: CGPoint, glowRadius: CGFloat) -> CGContext {
    let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                        space: space, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
    ctx.setFillColor(rgb(10, 10, 11))
    ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
    let glow = CGGradient(colorsSpace: space, colors: [rgb(225, 77, 58, 0.45), rgb(255, 165, 61, 0.12), rgb(10, 10, 11, 0)] as CFArray,
                          locations: [0, 0.5, 1])!
    ctx.drawRadialGradient(glow, startCenter: glowAt, startRadius: 0, endCenter: glowAt, endRadius: glowRadius, options: [])
    return ctx
}

/// A screenshot in a rounded, shadowed frame, rotated by `angle` radians about its center.
func drawPhone(_ ctx: CGContext, _ image: CGImage, center: CGPoint, width: CGFloat, angle: CGFloat = 0) {
    let height = width * CGFloat(image.height) / CGFloat(image.width)
    let rect = CGRect(x: -width / 2, y: -height / 2, width: width, height: height)
    let path = CGPath(roundedRect: rect, cornerWidth: width * 0.11, cornerHeight: width * 0.11, transform: nil)
    ctx.saveGState()
    ctx.translateBy(x: center.x, y: center.y)
    ctx.rotate(by: angle)
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -width * 0.03), blur: width * 0.12, color: rgb(0, 0, 0, 0.75))
    ctx.addPath(path)
    ctx.setFillColor(rgb(0, 0, 0))
    ctx.fillPath()
    ctx.restoreGState()
    ctx.saveGState()
    ctx.addPath(path)
    ctx.clip()
    ctx.draw(image, in: rect)
    ctx.restoreGState()
    ctx.addPath(path)
    ctx.setStrokeColor(rgb(255, 255, 255, 0.16))
    ctx.setLineWidth(width * 0.006)
    ctx.strokePath()
    ctx.restoreGState()
}

/// The wing from the website's brand mark (32-point grid), filled with the brand gradient.
func drawWing(_ ctx: CGContext, in box: CGRect) {
    let s = box.width / 32
    func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: box.minX + x * s, y: box.maxY - y * s) }
    let path = CGMutablePath()
    path.move(to: p(3, 5))
    path.addCurve(to: p(15.7, 15.4), control1: p(8.5, 5.5), control2: p(12.4, 8.8))
    path.addCurve(to: p(29, 9.6), control1: p(20.5, 9.5), control2: p(25, 8.6))
    path.addCurve(to: p(22.2, 20.2), control1: p(27, 11.4), control2: p(24.5, 17.2))
    path.addCurve(to: p(13, 27), control1: p(20.4, 22.6), control2: p(16.3, 25.2))
    path.addCurve(to: p(10.9, 19.5), control1: p(13.4, 23.9), control2: p(12.5, 21.6))
    path.addCurve(to: p(3, 5), control1: p(6.6, 14.8), control2: p(3.8, 10.4))
    path.closeSubpath()
    ctx.saveGState()
    ctx.addPath(path)
    ctx.clip()
    let gradient = CGGradient(colorsSpace: space, colors: [rgb(255, 165, 61), rgb(255, 122, 95), rgb(225, 77, 58)] as CFArray, locations: [0, 0.5, 1])!
    ctx.drawLinearGradient(gradient, start: CGPoint(x: box.minX, y: box.maxY), end: CGPoint(x: box.maxX, y: box.minY), options: [])
    ctx.restoreGState()
}

func text(_ string: String, size: CGFloat, weight: NSFont.Weight, alpha: CGFloat = 1) -> NSAttributedString {
    NSAttributedString(string: string, attributes: [
        .font: NSFont.systemFont(ofSize: size, weight: weight),
        .foregroundColor: NSColor(white: 1, alpha: alpha), .kern: -size * 0.01
    ])
}

func save(_ ctx: CGContext, _ name: String) {
    let destination = CGImageDestinationCreateWithURL(out.appendingPathComponent(name) as CFURL, "public.png" as CFString, 1, nil)!
    CGImageDestinationAddImage(destination, ctx.makeImage()!, nil)
    CGImageDestinationFinalize(destination)
    print("wrote \(name)")
}

let home = screenshot("01-home.png"), note = screenshot("03-note.png"), search = screenshot("04-search.png")
try? FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)

do {
    let (w, h): (CGFloat, CGFloat) = (3840, 1646)
    let ctx = canvas(Int(w), Int(h), glowAt: CGPoint(x: w * 0.68, y: h * 0.45), glowRadius: w * 0.42)
    drawPhone(ctx, home, center: CGPoint(x: w * 0.58, y: h * 0.40), width: 560, angle: 0.10)
    drawPhone(ctx, search, center: CGPoint(x: w * 0.82, y: h * 0.40), width: 560, angle: -0.10)
    drawPhone(ctx, note, center: CGPoint(x: w * 0.70, y: h * 0.47), width: 620)
    NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: false)
    let left = w * 0.08
    drawWing(ctx, in: CGRect(x: left, y: h * 0.56, width: 230, height: 230))
    text("Volant", size: 250, weight: .bold).draw(at: CGPoint(x: left + 270, y: h * 0.56))
    text("Notes, snippets and quicklinks.", size: 108, weight: .semibold).draw(at: CGPoint(x: left, y: h * 0.38))
    text("On your iPhone and your Mac.", size: 108, weight: .semibold, alpha: 0.6).draw(at: CGPoint(x: left, y: h * 0.38 - 140))
    save(ctx, "header.png")
}

do {
    let (w, h): (CGFloat, CGFloat) = (3840, 2560)
    let ctx = canvas(Int(w), Int(h), glowAt: CGPoint(x: w / 2, y: h * 0.25), glowRadius: w * 0.6)
    let phone: CGFloat = 1000
    for (index, image) in [home, note, search].enumerated() {
        drawPhone(ctx, image, center: CGPoint(x: w * (0.22 + 0.28 * CGFloat(index)), y: h * 0.47), width: phone)
    }
    save(ctx, "search.png")
}
