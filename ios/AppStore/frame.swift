import AppKit

/// Frames one simulator screenshot for the App Store: Volant's dark background with a rust glow at
/// the top, a bold headline and a subline in the system font, and the screenshot below with
/// rounded corners. The output is an opaque PNG at the exact store size.
///
///   swift frame.swift <screenshot.png> <out.png> <width> <height> <headline> <subline>
let arguments = CommandLine.arguments
guard arguments.count == 7, let width = Int(arguments[3]), let height = Int(arguments[4]),
      let shot = NSImage(contentsOfFile: arguments[1])?.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
    FileHandle.standardError.write(Data("usage: frame.swift <in.png> <out.png> <width> <height> <headline> <subline>\n".utf8))
    exit(2)
}
let headline = arguments[5], subline = arguments[6]
let W = CGFloat(width), H = CGFloat(height)
let space = CGColorSpace(name: CGColorSpace.sRGB)!
let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                    space: space, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!

/// sRGB color from 0–255 components.
func rgb(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: r / 255, green: g / 255, blue: b / 255, alpha: a)
}

ctx.setFillColor(rgb(10, 10, 11))
ctx.fill(CGRect(x: 0, y: 0, width: W, height: H))
let glow = CGGradient(colorsSpace: space, colors: [rgb(225, 77, 58, 0.42), rgb(255, 165, 61, 0.10), rgb(10, 10, 11, 0)] as CFArray,
                      locations: [0, 0.45, 1])!
ctx.drawRadialGradient(glow, startCenter: CGPoint(x: W / 2, y: H * 1.02), startRadius: 0,
                       endCenter: CGPoint(x: W / 2, y: H * 1.02), endRadius: W * 0.95, options: [])

let portrait = H > W * 1.6
let shotWidth = W * (portrait ? 0.80 : 0.78)
let shotHeight = shotWidth * CGFloat(shot.height) / CGFloat(shot.width)
let top = H * (portrait ? 0.195 : 0.19)
let shotRect = CGRect(x: (W - shotWidth) / 2, y: H - top - shotHeight, width: shotWidth, height: shotHeight)
let radius = shotWidth * (portrait ? 0.075 : 0.035)
let rounded = CGPath(roundedRect: shotRect, cornerWidth: radius, cornerHeight: radius, transform: nil)

ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: -W * 0.01), blur: W * 0.05, color: rgb(0, 0, 0, 0.7))
ctx.addPath(rounded)
ctx.setFillColor(rgb(0, 0, 0))
ctx.fillPath()
ctx.restoreGState()
ctx.saveGState()
ctx.addPath(rounded)
ctx.clip()
ctx.draw(shot, in: shotRect)
ctx.restoreGState()
ctx.addPath(rounded)
ctx.setStrokeColor(rgb(255, 255, 255, 0.14))
ctx.setLineWidth(max(2, W * 0.002))
ctx.strokePath()

NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: false)
let center = NSMutableParagraphStyle()
center.alignment = .center
center.lineBreakMode = .byWordWrapping
let headlineSize = W * (portrait ? 0.074 : (H > W * 1.4 ? 0.06 : 0.046))
let headlineText = NSAttributedString(string: headline, attributes: [
    .font: NSFont.systemFont(ofSize: headlineSize, weight: .bold),
    .foregroundColor: NSColor.white, .paragraphStyle: center, .kern: -headlineSize * 0.01
])
let sublineText = NSAttributedString(string: subline, attributes: [
    .font: NSFont.systemFont(ofSize: headlineSize * 0.5, weight: .medium),
    .foregroundColor: NSColor(white: 1, alpha: 0.62), .paragraphStyle: center
])
let textWidth = W * 0.86
let headlineBox = headlineText.boundingRect(with: CGSize(width: textWidth, height: H), options: [.usesLineFragmentOrigin])
let sublineBox = sublineText.boundingRect(with: CGSize(width: textWidth, height: H), options: [.usesLineFragmentOrigin])
let gap = headlineSize * 0.35
let block = headlineBox.height + gap + sublineBox.height
let blockTop = H - (top - block) / 2 - headlineSize * 0.05
headlineText.draw(with: CGRect(x: (W - textWidth) / 2, y: blockTop - headlineBox.height, width: textWidth, height: headlineBox.height),
                  options: [.usesLineFragmentOrigin])
sublineText.draw(with: CGRect(x: (W - textWidth) / 2, y: blockTop - headlineBox.height - gap - sublineBox.height, width: textWidth, height: sublineBox.height),
                 options: [.usesLineFragmentOrigin])

let image = ctx.makeImage()!
let destination = CGImageDestinationCreateWithURL(URL(fileURLWithPath: arguments[2]) as CFURL, "public.png" as CFString, 1, nil)!
CGImageDestinationAddImage(destination, image, nil)
CGImageDestinationFinalize(destination)
