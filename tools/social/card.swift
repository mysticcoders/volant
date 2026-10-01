import AppKit

/// Draws the 1280×640 social card offscreen; no window is shown.
let size = NSSize(width: 1280, height: 640)
let icon = NSImage(contentsOfFile: CommandLine.arguments[1])!
let output = CommandLine.arguments[2]
func color(_ hex: UInt32, _ alpha: CGFloat = 1) -> NSColor {
    NSColor(srgbRed: CGFloat(hex >> 16 & 0xff) / 255, green: CGFloat(hex >> 8 & 0xff) / 255, blue: CGFloat(hex & 0xff) / 255, alpha: alpha)
}
let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size.width), pixelsHigh: Int(size.height), bitsPerSample: 8,
                           samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
color(0x141516).setFill()
NSRect(origin: .zero, size: size).fill()
// A soft coral glow behind the icon, in the site's primary color.
let glow = NSGradient(colors: [color(0xff8b78, 0.28), color(0xff8b78, 0.0)])!
glow.draw(fromCenter: NSPoint(x: 300, y: 320), radius: 0, toCenter: NSPoint(x: 300, y: 320), radius: 330, options: [])
// The icon artwork is an opaque square; macOS masks it to a rounded square when shown, so the
// card does the same, with a soft shadow like the Dock's.
let iconRect = NSRect(x: 120, y: 140, width: 360, height: 360)
let mask = NSBezierPath(roundedRect: iconRect, xRadius: 360 * 0.2237, yRadius: 360 * 0.2237)
NSGraphicsContext.saveGraphicsState()
let shadow = NSShadow()
shadow.shadowColor = NSColor.black.withAlphaComponent(0.45)
shadow.shadowBlurRadius = 28
shadow.shadowOffset = NSSize(width: 0, height: -10)
shadow.set()
color(0xfdfaf3).setFill()
mask.fill()
NSGraphicsContext.restoreGraphicsState()
NSGraphicsContext.saveGraphicsState()
mask.addClip()
icon.draw(in: iconRect)
NSGraphicsContext.restoreGraphicsState()
func draw(_ text: String, size: CGFloat, weight: NSFont.Weight, color: NSColor, at point: NSPoint, tracking: CGFloat = 0) {
    let attributes: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: size, weight: weight), .foregroundColor: color, .kern: tracking]
    NSAttributedString(string: text, attributes: attributes).draw(at: point)
}
draw("Volant", size: 112, weight: .bold, color: color(0xf1efeb), at: NSPoint(x: 560, y: 368), tracking: -2)
draw("Your Mac. Your agents.", size: 44, weight: .semibold, color: color(0xf1efeb), at: NSPoint(x: 564, y: 292))
draw("One shortcut away.", size: 44, weight: .semibold, color: color(0xff8b78), at: NSPoint(x: 564, y: 238))
draw("Open-source macOS launcher  ·  MIT  ·  usevolant.com", size: 24, weight: .regular, color: color(0xa7a6a3), at: NSPoint(x: 566, y: 150))
NSGraphicsContext.restoreGraphicsState()
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: output))
