import AppKit
import SwiftUI
import CryptoKit
import SQLite3
import VolantCore

// Renders the 10-feature demo video as numbered 1080x1080 frames of the real Volant views with
// fictional data: /tmp/volant-video-SS-NNNN-MS.png, where SS is the scene (00 for the end card) and
// MS is how long the frame shows. tools/render-video.sh runs it in the render VM through
// tools/render-vm.py --video and encodes the frames into one clip per scene and the full video.
// The scenes, their card text and their scripted keys, clicks and timings are in scenes.json.
setbuf(stdout, nil)
let app = NSApplication.shared
app.setActivationPolicy(.regular)
app.appearance = NSAppearance(named: .darkAqua)
let root = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : NSTemporaryDirectory())
    .appendingPathComponent("volant-video-" + UUID().uuidString)
try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
let resources = Bundle.main.resourceURL!

/// Stops the render with a message naming the scene, as the fixtures do.
func fail(_ message: String) -> Never {
    fputs("FAIL: \(message) [scene \(currentScene)]\n", stderr)
    exit(1)
}

/// Runs the main run loop until the condition holds or `timeout` passes.
@discardableResult
func waitUntil(timeout: TimeInterval = 3, _ condition: () -> Bool) -> Bool {
    let deadline = Date().addingTimeInterval(timeout)
    while Date() < deadline {
        if condition() { return true }
        RunLoop.main.run(until: Date().addingTimeInterval(0.02))
    }
    return condition()
}

func settle(_ seconds: TimeInterval = 0.2) { RunLoop.main.run(until: Date().addingTimeInterval(seconds)) }

// MARK: - Scene list

struct Step: Decodable {
    var stage: String?
    var type: String?
    var into: String?
    var key: String?
    var hook: String?
    var cursor: CursorTarget?
    var moveMs: Int?
    var click: Bool?
    var hideCursor: Bool?
    var reveal: Int?
    var holdMs: Int?
    var keyMs: Int?
    var `repeat`: Int?
}

/// A cursor destination: an anchor the fixture resolves, or a point on the 1080 canvas.
enum CursorTarget: Decodable {
    case anchor(String)
    case point(CGFloat, CGFloat)

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let name = try? container.decode(String.self) { self = .anchor(name); return }
        let values = try container.decode([CGFloat].self)
        self = .point(values[0], values[1])
    }
}

struct Scene: Decodable {
    let number: Int
    let title: String
    let caption: String
    let note: String?
    let fixture: String
    let steps: [Step]
}

struct SceneList: Decodable {
    let cardMs: Int
    let endMs: Int
    let scenes: [Scene]
}

let sceneURL = resources.appendingPathComponent("scenes.json")
let sceneList = try JSONDecoder().decode(SceneList.self, from: Data(contentsOf: sceneURL))
/// `scenes=1,4,0` renders only those scenes; 0 is the end card.
let onlyScenes = CommandLine.arguments.first { $0.hasPrefix("scenes=") }
    .map { Set($0.dropFirst("scenes=".count).split(separator: ",").compactMap { Int($0) }) }

// MARK: - Look

/// The website's dark palette (website/app/home.css) and the app's accent color.
enum Palette {
    static func hex(_ value: UInt32, _ alpha: CGFloat = 1) -> NSColor {
        NSColor(srgbRed: CGFloat(value >> 16 & 0xff) / 255, green: CGFloat(value >> 8 & 0xff) / 255, blue: CGFloat(value & 0xff) / 255, alpha: alpha)
    }
    static let background = hex(0x141b22)
    static let foreground = hex(0xedf0f4)
    static let muted = hex(0xadb9c5)
    static let primary = hex(0xa8c0ff)
    static let surface = hex(0x1f2b36)
    static let border = hex(0x35424e)
    static let accent = hex(0xff7a5f)
}

let canvasSize: CGFloat = 1080
/// The area above the caption where a stage draws its windows.
let stageArea = NSRect(x: 40, y: 200, width: 1000, height: 850)

/// Draws `text` centered horizontally within `width` around `centerX`, wrapping as needed, with
/// its top at `top`; returns the height used.
@discardableResult
func drawCentered(_ text: String, size: CGFloat, weight: NSFont.Weight, color: NSColor, top: CGFloat, width: CGFloat = 960,
                  centerX: CGFloat = canvasSize / 2, tracking: CGFloat = 0) -> CGFloat {
    let paragraph = NSMutableParagraphStyle()
    paragraph.alignment = .center
    paragraph.lineBreakMode = .byWordWrapping
    paragraph.lineHeightMultiple = 1.08
    let string = NSAttributedString(string: text, attributes: [.font: NSFont.systemFont(ofSize: size, weight: weight), .foregroundColor: color,
                                                               .paragraphStyle: paragraph, .kern: tracking])
    let bounds = string.boundingRect(with: NSSize(width: width, height: 1000), options: [.usesLineFragmentOrigin, .usesFontLeading])
    let height = ceil(bounds.height)
    string.draw(with: NSRect(x: centerX - width / 2, y: top - height, width: width, height: height), options: [.usesLineFragmentOrigin, .usesFontLeading])
    return height
}

/// Draws an image into `rect`, clipped to rounded corners, with a soft shadow beneath.
func drawWindowImage(_ image: CGImage, in rect: NSRect, radius: CGFloat, shadow: Bool = true) {
    let path = NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)
    if shadow {
        NSGraphicsContext.saveGraphicsState()
        let shade = NSShadow()
        shade.shadowColor = NSColor.black.withAlphaComponent(0.55)
        shade.shadowBlurRadius = 40
        shade.shadowOffset = NSSize(width: 0, height: -14)
        shade.set()
        Palette.background.setFill()
        path.fill()
        NSGraphicsContext.restoreGraphicsState()
    }
    NSGraphicsContext.saveGraphicsState()
    path.addClip()
    NSGraphicsContext.current?.imageInterpolation = .high
    NSImage(cgImage: image, size: rect.size).draw(in: rect)
    NSGraphicsContext.restoreGraphicsState()
    NSGraphicsContext.saveGraphicsState()
    NSColor.white.withAlphaComponent(0.12).setStroke()
    path.lineWidth = 1
    path.stroke()
    NSGraphicsContext.restoreGraphicsState()
}

/// A fictional wallpaper in the site's colors, for stages that stand for the screen.
func drawWallpaper(in rect: NSRect) {
    NSGradient(colors: [Palette.hex(0x304b7c), Palette.hex(0x1c2833), Palette.hex(0x141b22)])!.draw(in: rect, angle: -60)
    let glow = NSGradient(colors: [Palette.hex(0xff7a5f, 0.22), Palette.hex(0xff7a5f, 0)])!
    glow.draw(fromCenter: NSPoint(x: rect.maxX - 160, y: rect.minY + 120), radius: 0, toCenter: NSPoint(x: rect.maxX - 160, y: rect.minY + 120), radius: 520, options: [])
}

// MARK: - Capture

typealias WindowImage = @convention(c) (CGRect, UInt32, UInt32, UInt32) -> Unmanaged<CGImage>?
let windowImage = dlsym(dlopen(nil, RTLD_NOW), "CGWindowListCreateImage").map { unsafeBitCast($0, to: WindowImage.self) }

/// The window as the window server draws it, materials and rounded corners included, or its content
/// view drawn offscreen when the window isn't on screen or the window server refuses.
func capture(_ window: NSWindow, offscreen: Bool = false) -> CGImage {
    window.contentView!.layoutSubtreeIfNeeded()
    if !offscreen, window.isVisible, let windowImage,
       let image = windowImage(.null, 1 << 3, UInt32(window.windowNumber), 1 | 8)?.takeRetainedValue(), image.width > 4 {
        return image
    }
    let view = window.contentView!
    let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds)!
    view.cacheDisplay(in: view.bounds, to: rep)
    return rep.cgImage!
}

// MARK: - Frames

var currentScene = 0
var frameNumber = 0
var cursorPoint: NSPoint?
var cursorPressed = false
/// Where the current stage drew its main window, so anchors in window points map to the canvas.
var placement: (window: NSWindow, rect: NSRect)?
var stage = "launcher"
var stageCaption: (String, String?)?
var cardText: (Int, String) = (0, "")

/// Composes the current stage, caption and cursor into one canvas and writes it to show for `ms`.
func emit(_ ms: Int) {
    guard ms > 0 else { return }
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(canvasSize), pixelsHigh: Int(canvasSize), bitsPerSample: 8, samplesPerPixel: 4,
                               hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    rep.size = NSSize(width: canvasSize, height: canvasSize)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    Palette.background.setFill()
    NSRect(x: 0, y: 0, width: canvasSize, height: canvasSize).fill()
    drawStage()
    if let (caption, note) = stageCaption {
        let used = drawCentered(caption, size: 34, weight: .medium, color: Palette.foreground, top: 168, width: 940)
        if let note { drawCentered(note, size: 22, weight: .regular, color: Palette.muted, top: 168 - used - 14, width: 940) }
    }
    if let cursorPoint { drawCursor(at: cursorPoint) }
    NSGraphicsContext.restoreGraphicsState()
    let name = String(format: "/tmp/volant-video-%02d-%04d-%d.png", currentScene, frameNumber, ms)
    do { try rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: name)) } catch { fail("Couldn't write \(name): \(error)") }
    frameNumber += 1
}

/// Draws the system arrow, or the crosshair while picking a color, with its hot spot at `point`,
/// and a ring while it is pressed.
func drawCursor(at point: NSPoint) {
    let cursor = stage == "pick-screen" ? NSCursor.crosshair : NSCursor.arrow
    let scale: CGFloat = 1.8
    let size = NSSize(width: cursor.image.size.width * scale, height: cursor.image.size.height * scale)
    if cursorPressed {
        let ring = NSBezierPath(ovalIn: NSRect(x: point.x - 26, y: point.y - 26, width: 52, height: 52))
        Palette.accent.withAlphaComponent(0.35).setFill()
        ring.fill()
        Palette.accent.setStroke()
        ring.lineWidth = 3
        ring.stroke()
    }
    let origin = NSPoint(x: point.x - cursor.hotSpot.x * scale, y: point.y - (cursor.image.size.height - cursor.hotSpot.y) * scale)
    cursor.image.draw(in: NSRect(origin: origin, size: size))
}

/// Writes a title card: the scene number small and grey above its one-line title.
func titleCard(_ scene: Scene, ms: Int) {
    let saved = (stage, cursorPoint, stageCaption)
    stage = "card"; cursorPoint = nil; stageCaption = nil
    cardText = (scene.number, scene.title)
    emit(ms)
    (stage, cursorPoint, stageCaption) = saved
}

/// Draws the plain-background title card or the end card.
func drawCard() {
    if stage == "end" {
        let icon = NSImage(contentsOf: resources.appendingPathComponent("AppIcon.png"))!
        let rect = NSRect(x: canvasSize / 2 - 130, y: 560, width: 260, height: 260)
        let mask = NSBezierPath(roundedRect: rect, xRadius: 260 * 0.2237, yRadius: 260 * 0.2237)
        NSGraphicsContext.saveGraphicsState()
        let shade = NSShadow()
        shade.shadowColor = NSColor.black.withAlphaComponent(0.5)
        shade.shadowBlurRadius = 30
        shade.shadowOffset = NSSize(width: 0, height: -10)
        shade.set()
        Palette.hex(0xfdfaf3).setFill()
        mask.fill()
        NSGraphicsContext.restoreGraphicsState()
        NSGraphicsContext.saveGraphicsState()
        mask.addClip()
        icon.draw(in: rect)
        NSGraphicsContext.restoreGraphicsState()
        drawCentered("Volant", size: 84, weight: .bold, color: Palette.foreground, top: 520, tracking: -1.5)
        drawCentered("usevolant.com", size: 44, weight: .semibold, color: Palette.primary, top: 400)
        drawCentered("Free and open source for macOS", size: 34, weight: .regular, color: Palette.muted, top: 330)
        return
    }
    drawCentered("#\(cardText.0)", size: 40, weight: .semibold, color: Palette.muted, top: 610)
    drawCentered(cardText.1, size: 72, weight: .bold, color: Palette.foreground, top: 548, width: 1000, tracking: -1)
}

// MARK: - Stages

/// Draws whatever the current stage shows.
func drawStage() {
    switch stage {
    case "card", "end": drawCard()
    case "launcher": drawLauncher()
    case "notch": drawNotchScreen()
    case "break-notice": drawBreakNotice()
    case "break-overlay": drawBreakOverlay()
    case "pick-screen": drawPickScreen()
    case "rex-overview": drawFitted(rexWindow!, maxWidth: 1000, radius: 12)
    case "notes": drawFitted(notesPanel!, maxWidth: 900, maxHeight: 820, radius: 14)
    case "notes-iphone": drawNotesWithPhone()
    case "settings": drawFitted(settings!.window!, maxWidth: 1000, radius: 12)
    default: fail("Unknown stage \(stage)")
    }
}

/// Fits a window's capture into the stage area, centered, and records where it went.
func drawFitted(_ window: NSWindow, maxWidth: CGFloat, maxHeight: CGFloat = stageArea.height, radius: CGFloat, centerX: CGFloat = canvasSize / 2) {
    let image = capture(window)
    let points = window.frame.size
    let scale = min(maxWidth / points.width, maxHeight / points.height)
    let size = NSSize(width: points.width * scale, height: points.height * scale)
    let rect = NSRect(x: (centerX - size.width / 2).rounded(), y: (stageArea.midY - size.height / 2).rounded(), width: size.width.rounded(), height: size.height.rounded())
    drawWindowImage(image, in: rect, radius: radius * scale)
    placement = (window, rect)
}

func drawLauncher() {
    drawFitted(panel, maxWidth: 1040, radius: 18)
}

/// A crop of the top of a MacBook screen at `notchScale` pixels per point: the lid, a fictional
/// wallpaper, the menu bar with a clock, the camera notch, and Volant's notch panel around it. While
/// `notchReveal` is set, the panel's final layout is revealed by a growing edge, as the panel does.
func drawNotchScreen() {
    let screenTop: CGFloat = 1010
    let screenRect = NSRect(x: 0, y: stageArea.minY + 20, width: canvasSize, height: screenTop - stageArea.minY - 20)
    Palette.hex(0x0b0d10).setFill()
    NSRect(x: 0, y: screenTop, width: canvasSize, height: canvasSize - screenTop).fill()
    NSGraphicsContext.saveGraphicsState()
    NSBezierPath(rect: screenRect).addClip()
    drawWallpaper(in: screenRect)
    let menuHeight: CGFloat = fakeNotchHeight * notchScale
    NSColor.black.withAlphaComponent(0.35).setFill()
    NSRect(x: 0, y: screenTop - menuHeight, width: canvasSize, height: menuHeight).fill()
    drawMenuBarStatus(rightEdge: canvasSize - 30, centerY: screenTop - menuHeight / 2, clockText: "9:41", size: 22)
    let notchRect = NSRect(x: canvasSize / 2 - fakeNotchWidth * notchScale, y: screenTop - menuHeight, width: fakeNotchWidth * 2 * notchScale, height: menuHeight)
    NSColor.black.setFill()
    NSBezierPath(roundedRect: notchRect, xRadius: 16, yRadius: 16).fill()
    NSRect(x: notchRect.minX, y: notchRect.midY, width: notchRect.width, height: notchRect.height / 2).fill()
    if let notch = focusNotch, notch.isVisible {
        let image = capture(notch, offscreen: true)
        let size = NSSize(width: notch.frame.width * notchScale, height: notch.frame.height * notchScale)
        let rect = NSRect(x: canvasSize / 2 - size.width / 2, y: screenTop - size.height, width: size.width, height: size.height)
        NSGraphicsContext.saveGraphicsState()
        if let (from, progress) = notchReveal {
            let width = from.width * notchScale + (size.width - from.width * notchScale) * progress
            let height = from.height * notchScale + (size.height - from.height * notchScale) * progress
            let clip = NSRect(x: canvasSize / 2 - width / 2, y: screenTop - height, width: width, height: height)
            let radius = min(clip.height / 2, 14 + 18 * progress)
            let shape = NSBezierPath(rect: NSRect(x: clip.minX, y: clip.midY, width: clip.width, height: clip.height / 2))
            shape.append(NSBezierPath(roundedRect: clip, xRadius: radius, yRadius: radius))
            shape.windingRule = .nonZero
            shape.addClip()
        }
        NSImage(cgImage: image, size: size).draw(in: rect)
        NSGraphicsContext.restoreGraphicsState()
        placement = (notch, rect)
    }
    NSGraphicsContext.restoreGraphicsState()
}

/// The clock and two status symbols at the right of a fictional menu bar.
func drawMenuBarStatus(rightEdge: CGFloat, centerY: CGFloat, clockText: String = "Thu Nov 12  9:41", size: CGFloat = 26) {
    let clock = NSAttributedString(string: clockText, attributes: [.font: NSFont.systemFont(ofSize: size, weight: .medium), .foregroundColor: NSColor.white])
    let clockSize = clock.size()
    clock.draw(at: NSPoint(x: rightEdge - clockSize.width, y: centerY - clockSize.height / 2))
    var x = rightEdge - clockSize.width - 30
    for name in ["battery.75percent", "wifi"] {
        guard let symbol = NSImage(systemSymbolName: name, accessibilityDescription: nil)?
            .withSymbolConfiguration(.init(pointSize: size, weight: .medium).applying(.init(paletteColors: [.white]))) else { continue }
        x -= symbol.size.width
        symbol.draw(in: NSRect(x: x, y: centerY - symbol.size.height / 2, width: symbol.size.width, height: symbol.size.height))
        x -= size
    }
}

/// The top-right corner of the screen at two pixels per point, with the break heads-up where
/// Volant puts it: 16 points in from the corner of the visible frame.
func drawBreakNotice() {
    let screenTop: CGFloat = 1010
    let screenRect = NSRect(x: 0, y: stageArea.minY + 20, width: canvasSize - 40, height: screenTop - stageArea.minY - 20)
    Palette.hex(0x0b0d10).setFill()
    NSRect(x: 0, y: stageArea.minY, width: canvasSize, height: canvasSize - stageArea.minY).fill()
    NSGraphicsContext.saveGraphicsState()
    NSBezierPath(rect: screenRect).addClip()
    NSBezierPath(roundedRect: NSRect(x: screenRect.minX - 80, y: screenRect.minY - 80, width: screenRect.width + 80, height: screenRect.height + 80), xRadius: 40, yRadius: 40).addClip()
    drawWallpaper(in: screenRect)
    let menuHeight: CGFloat = 48
    NSColor.black.withAlphaComponent(0.35).setFill()
    NSRect(x: 0, y: screenTop - menuHeight, width: canvasSize, height: menuHeight).fill()
    drawMenuBarStatus(rightEdge: screenRect.maxX - 30, centerY: screenTop - menuHeight / 2)
    if let notice = breakPresenter?.notice, notice.isVisible {
        let image = capture(notice)
        let scale = CGFloat(image.width) / notice.frame.width
        let size = NSSize(width: CGFloat(image.width) * 2 / scale, height: CGFloat(image.height) * 2 / scale)
        let rect = NSRect(x: screenRect.maxX - 32 - size.width, y: screenTop - menuHeight - 32 - size.height, width: size.width, height: size.height)
        NSImage(cgImage: image, size: size).draw(in: rect)
        placement = (notice, rect)
    }
    NSGraphicsContext.restoreGraphicsState()
}

/// The whole screen during a Standard break, in a thin bezel.
func drawBreakOverlay() {
    guard let overlay = breakPresenter?.overlays.first else { fail("No break overlay is showing") }
    let image = capture(overlay)
    let points = overlay.frame.size
    let width: CGFloat = 1000
    let size = NSSize(width: width, height: (width * points.height / points.width).rounded())
    let rect = NSRect(x: (canvasSize - width) / 2, y: (stageArea.midY - size.height / 2).rounded(), width: width, height: size.height)
    let zoom: CGFloat = 1.45
    let zoomed = NSRect(x: rect.midX - rect.width * zoom / 2, y: rect.midY - rect.height * zoom / 2, width: rect.width * zoom, height: rect.height * zoom)
    Palette.hex(0x0b0d10).setFill()
    NSBezierPath(roundedRect: rect.insetBy(dx: -14, dy: -14), xRadius: 26, yRadius: 26).fill()
    NSGraphicsContext.saveGraphicsState()
    NSBezierPath(roundedRect: rect, xRadius: 14, yRadius: 14).addClip()
    drawWallpaper(in: rect)
    NSImage(cgImage: image, size: size).draw(in: zoomed)
    NSGraphicsContext.restoreGraphicsState()
}

/// A fictional poster on a fictional screen to pick a color from. The macOS color loupe is system
/// UI that only appears on a real display, so the crosshair stands in for it.
func drawPickScreen() {
    let rect = NSRect(x: 40, y: stageArea.minY + 30, width: 1000, height: 790)
    Palette.hex(0x0b0d10).setFill()
    NSBezierPath(roundedRect: rect.insetBy(dx: -14, dy: -14), xRadius: 26, yRadius: 26).fill()
    NSGraphicsContext.saveGraphicsState()
    NSBezierPath(roundedRect: rect, xRadius: 14, yRadius: 14).addClip()
    drawWallpaper(in: rect)
    let poster = NSRect(x: 230, y: 330, width: 620, height: 470)
    Palette.hex(0xf7f7f2).setFill()
    NSBezierPath(roundedRect: poster, xRadius: 18, yRadius: 18).fill()
    let swatches: [(UInt32, NSRect)] = [
        (0x244dba, NSRect(x: 270, y: 470, width: 170, height: 290)),
        (0xff6363, NSRect(x: 460, y: 470, width: 170, height: 290)),
        (0xf2c14e, NSRect(x: 650, y: 470, width: 160, height: 290)),
    ]
    for (color, swatch) in swatches {
        Palette.hex(color).setFill()
        NSBezierPath(roundedRect: swatch, xRadius: 12, yRadius: 12).fill()
    }
    let label = NSAttributedString(string: "Fictional poster", attributes: [.font: NSFont.systemFont(ofSize: 30, weight: .semibold), .foregroundColor: Palette.hex(0x202c35)])
    label.draw(at: NSPoint(x: 272, y: 395))
    NSGraphicsContext.restoreGraphicsState()
}

/// The Mac notes window beside the existing iPhone capture of the same fictional note.
func drawNotesWithPhone() {
    drawFitted(notesPanel!, maxWidth: 620, maxHeight: 760, radius: 14, centerX: 350)
    let phone = NSImage(contentsOf: resources.appendingPathComponent("iphone-note.webp"))!
    let height: CGFloat = 780
    let width = (height * phone.size.width / phone.size.height).rounded()
    let rect = NSRect(x: 1040 - width, y: (stageArea.midY - height / 2).rounded(), width: width, height: height)
    Palette.hex(0x0b0d10).setFill()
    let bezel = NSBezierPath(roundedRect: rect.insetBy(dx: -12, dy: -12), xRadius: 64, yRadius: 64)
    bezel.fill()
    Palette.border.setStroke()
    bezel.lineWidth = 2
    bezel.stroke()
    NSGraphicsContext.saveGraphicsState()
    NSBezierPath(roundedRect: rect, xRadius: 52, yRadius: 52).addClip()
    phone.draw(in: rect)
    NSGraphicsContext.restoreGraphicsState()
}

// MARK: - Fixtures

let clipboard = ClipboardStore(retention: 10, storageURL: root.appendingPathComponent("clipboard.sqlite"), encryptionKey: SymmetricKey(size: .bits256))
var panel: LauncherPanel!
var chatConfig: AIConfiguration?
var videoClock = Date(timeIntervalSince1970: 1_800_000_000)
var focusNotch: FocusNotchPanel?
var breakController: BreakController?
var breakPresenter: BreakPresenter?
var rexWindow: NSWindow?
var notesPanel: NotesPanel?
var settings: SettingsWindowController?
var rexController: RexOverviewWindowController?
var hooks: [String: () -> Void] = [:]
let fakeNotchWidth: CGFloat = 95
let fakeNotchHeight: CGFloat = 32
/// Canvas pixels per point on the notch stage.
let notchScale: CGFloat = 1.6
/// While set, the notch panel is revealed from the given collapsed size by the given fraction.
var notchReveal: (NSSize, CGFloat)?
let fixtureIcon = Data(base64Encoded: "UklGRh4AAABXRUJQVlA4TBEAAAAvH8AHAAdQvKIUuf+BiOh/AAA=")!
let positions = UserDefaults(suiteName: "volant.video.fixture")!

/// Replaces the launcher with a fresh hidden one over isolated stores, an empty configuration file
/// and a Focus controller on the video clock, so no scene depends on another.
func freshLauncher() {
    panel?.orderOut(nil)
    let id = UUID().uuidString
    let focus = FocusController(stateURL: root.appendingPathComponent("focus-\(id).json"), defaults: positions, clock: { videoClock },
                                hide: { _ in true }, frontmost: { nil }, automaticTimer: false, restore: false)
    positions.removeObject(forKey: "launcherPosition")
    panel = LauncherPanel(index: AppIndex(entries: []), clipboard: clipboard, notes: NotesStore(directory: root.appendingPathComponent("Notes-\(id)")),
                          config: Preferences(), usage: UsageStore(url: root.appendingPathComponent("usage-\(id).sqlite")), positionStore: positions,
                          focus: focus, files: FileSearch(home: .unavailable)) { action in
        if case .ai = action {
            _ = panel.model.acp.openChat(configuration: chatConfig, connect: {
                panel.model.acp.state.phase = "ready"
                panel.model.acp.state.status = "Connected"
            })
        }
    }
    panel.model.searchesSecondarySources = false
    panel.model.actionConfigURL = root.appendingPathComponent("config-\(id).json")
    try! Data("{}".utf8).write(to: panel.model.actionConfigURL)
    panel.model.copyText = { _ in }
}

/// Shows the launcher with its search field focused, as a summon does.
func summon() {
    panel.toggle()
    waitUntil { panel.isKeyWindow && panel.firstResponder is NSTextView }
    settle(0.3)
}

/// Sends a key to a window the way NSApplication would: command equivalents first.
func sendKey(_ name: String, to window: NSWindow) {
    let table: [String: (String, UInt16, NSEvent.ModifierFlags)] = [
        "return": ("\r", 36, []), "down": ("\u{F701}", 125, []), "up": ("\u{F700}", 126, []), "right": ("\u{F703}", 124, []),
        "left": ("\u{F702}", 123, []), "tab": ("\t", 48, []), "escape": ("\u{1b}", 53, []), "cmd-k": ("k", 40, .command), "cmd-p": ("p", 35, .command),
    ]
    guard let (characters, code, modifiers) = table[name] else { fail("Unknown key \(name)") }
    let event = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: modifiers, timestamp: ProcessInfo.processInfo.systemUptime,
                                 windowNumber: window.windowNumber, context: nil, characters: characters, charactersIgnoringModifiers: characters,
                                 isARepeat: false, keyCode: code)!
    if !modifiers.contains(.command) || !window.performKeyEquivalent(with: event) { window.sendEvent(event) }
    settle(0.25)
}

/// Puts the caret at the end of whatever field is being typed in, as typing leaves it.
func caretToEnd() {
    if let editor = panel.firstResponder as? NSTextView { editor.setSelectedRange(NSRange(location: (editor.string as NSString).length, length: 0)) }
}

/// Every text field in a view hierarchy.
func fields(_ view: NSView) -> [NSTextField] { (view as? NSTextField).map { [$0] } ?? view.subviews.flatMap(fields) }

// Focus: the launcher rows and form, then the session around a fake notch and a blocked app's
// reminder dropping out of it. No app is hidden and nothing is saved outside the temporary folder.
func focusFixture() {
    freshLauncher()
    summon()
    let screen = NSScreen.main ?? NSScreen.screens[0]
    let notch = NSRect(x: screen.frame.midX - fakeNotchWidth, y: screen.frame.maxY - fakeNotchHeight, width: fakeNotchWidth * 2, height: fakeNotchHeight)
    hooks["focus.addBlocks"] = {
        panel.model.entryForm?.focus?.add(.app(bundleIdentifier: "com.example.chat", name: "Chat"))
        panel.model.entryForm?.focus?.add(.website("news.example.com"))
    }
    hooks["focus.start"] = {
        guard let draft = panel.model.entryForm, panel.model.saveEntry(draft) else { fail("The Focus form didn't start a session") }
        panel.orderOut(nil)
        let notchPanel = FocusNotchPanel(controller: panel.model.focus, actions: FocusBarActions(), snoozeMinutes: { 3 }, geometry: { (screen, notch) })
        notchPanel.appearance = app.appearance
        notchPanel.refresh()
        focusNotch = notchPanel
        waitUntil { notchPanel.isVisible }
    }
    hooks["focus.expand"] = { focusNotch?.state.expanded = true; videoClock += 2; panel.model.focus.tick() }
    hooks["focus.collapse"] = { focusNotch?.state.expanded = false; settle(0.6) }
    hooks["focus.blockedApp"] = {
        videoClock += 3
        panel.model.focus.tick()
        panel.model.focus.handleActivation(bundleIdentifier: "com.example.chat", name: "Chat") { true }
    }
}

// Breaks: a fictional schedule on the video clock reaches its heads-up, then a Standard break that
// covers the screen and counts down. No idle time, camera or microphone is read.
func breaksFixture() {
    let controller = BreakController(preferences: BreakPreferences(enabled: true), stateURL: root.appendingPathComponent("breaks.json"),
                                     clock: { videoClock }, idleSeconds: { 0 }, inCall: { false }, automaticTimer: false, restore: false)
    controller.start()
    let presenter = BreakPresenter(controller: controller)
    presenter.notice.appearance = app.appearance
    breakController = controller
    breakPresenter = presenter
    /// Moves the video clock forward a second at a time, ticking the schedule each time.
    func advance(_ seconds: Int) {
        for _ in 0..<seconds { videoClock += 1; controller.tick() }
    }
    hooks["breaks.headsUp"] = {
        advance(44 * 60)
        presenter.refresh()
        waitUntil { presenter.notice.isVisible }
        presenter.notice.makeFirstResponder(nil)
        settle(0.3)
    }
    hooks["breaks.begin"] = {
        advance(60)
        presenter.refresh()
        waitUntil { !presenter.overlays.isEmpty && presenter.overlays.allSatisfy(\.isVisible) }
        presenter.overlays.forEach { $0.appearance = app.appearance }
        advance(1)
        settle(0.4)
    }
    hooks["breaks.tick"] = { advance(1); settle(0.1) }
}

// Extension Catalog: the real published catalog, fetched and verified on the host by fetch-catalog.py
// and bundled as catalog-fixture, served to the real catalog view at the same paths the fetch helper
// reads, and checked again here with the app's production key and icon hashes. Packages aren't
// bundled, so nothing is installed.
func catalogFixture() throws {
    freshLauncher()
    let folder = resources.appendingPathComponent("catalog-fixture")
    guard FileManager.default.fileExists(atPath: folder.appendingPathComponent("catalog.json").path) else {
        fail("No catalog fixture; run tools/marketing/video/fetch-catalog.py")
    }
    let manager = ExtensionManager(configURL: panel.model.actionConfigURL, roots: [Bundle.main.url(forResource: "HelloWorld", withExtension: nil)!])
    manager.reload()
    try manager.setCommunityAllowed(true, expected: false)
    panel.model.extensions = manager
    panel.model.catalog.client = ExtensionCatalogClient(fetchFile: { path, limit, completion in
        guard let data = try? Data(contentsOf: folder.appendingPathComponent(path)), data.count <= limit else {
            completion(.failure(ExtensionCatalogError.unavailable("The video fixture has no packages.")))
            return
        }
        completion(.success(data))
    }, publicKey: ExtensionCatalogKey.publicKey, stateURL: root.appendingPathComponent("catalog-state.json"))
    summon()
    hooks["catalog.check"] = {
        guard let field = fields(panel.contentView!).first(where: { $0.placeholderString == "Search extensions…" }) else { fail("No catalog search field") }
        panel.makeFirstResponder(field)
        sendKey("return", to: panel)
        guard waitUntil(timeout: 8, { panel.model.catalog.listings.count == catalogFacts.count }) else {
            fail("The catalog fixture didn't load \(catalogFacts.count) listings: \(panel.model.catalog.listings.count)")
        }
        guard waitUntil(timeout: 8, { panel.model.catalog.listings.allSatisfy { ExtensionCatalogIcons.shared.image(for: $0) != nil } }) else {
            fail("Not every catalog icon matched the signed index")
        }
        settle(0.4)
    }
}

/// What fetch-catalog.py recorded about the bundled catalog: the date it was fetched and how many
/// extensions it lists, for the scene's note.
let catalogFacts: (date: String, count: Int) = {
    let url = resources.appendingPathComponent("catalog-fixture/fetched.json")
    guard let data = try? Data(contentsOf: url), let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
          let day = object["fetched"] as? String, let count = object["extensions"] as? Int else { return ("", 0) }
    let parser = DateFormatter()
    parser.locale = Locale(identifier: "en_US_POSIX")
    parser.timeZone = TimeZone(identifier: "UTC")
    parser.dateFormat = "yyyy-MM-dd"
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US")
    formatter.timeZone = TimeZone(identifier: "UTC")
    formatter.dateStyle = .long
    return (parser.date(from: day).map(formatter.string(from:)) ?? day, count)
}()

/// Fills a caption's `{catalogDate}` and `{catalogCount}` from the bundled catalog.
func filled(_ text: String) -> String {
    text.replacingOccurrences(of: "{catalogDate}", with: catalogFacts.date).replacingOccurrences(of: "{catalogCount}", with: "\(catalogFacts.count)")
}

// AI Chat: search text carried to an agent conversation with Tab, then a fictional exchange drawn
// by the real conversation view. No provider, helper or network connection is used.
func chatFixture() {
    freshLauncher()
    chatConfig = AIConfiguration()
    chatConfig?.provider = "claude"
    summon()
    let reply = [
        "The booking test fails because ", "`holdSeat` now returns before the fare is saved, ", "so the confirmation reads an empty fare.\n\n",
        "## Fix\n", "Await the save in `src/booking/hold.ts`:\n\n", "```ts\nawait fares.save(hold.fare)\nreturn hold\n```",
    ]
    var sent = 0
    hooks["chat.send"] = {
        let question = panel.model.acp.draft
        panel.model.acp.draft = ""
        panel.model.acp.state.messages = [ACPMessage(role: "You", text: question.isEmpty ? "Why does the booking test fail?" : question),
                                          ACPMessage(role: "Agent", text: "")]
        panel.model.acp.state.phase = "working"
        settle()
    }
    hooks["chat.stream"] = {
        guard sent < reply.count else { return }
        panel.model.acp.state.messages[1].text += reply[sent]
        sent += 1
        settle(0.1)
    }
    hooks["chat.finish"] = {
        while sent < reply.count { hooks["chat.stream"]!() }
        panel.model.acp.state.phase = "ready"
        settle()
    }
}

// Rex: fictional panes in the launcher through an injected watcher reply, then the Rex Overview
// window with fictional sessions and screen text. No Rex server or agent helper is reached.
func rexFixture() throws {
    freshLauncher()
    func pane(_ block: String, session: String, label: String, folder: String, state: RexState, message: String?) -> RexPane {
        RexPane(sessionID: "session:" + session, sessionLabel: label, blockID: "block:" + block, label: "shell", cwd: "/fictional/" + folder,
                status: RexStatus(state: state, kind: state == .blocked ? "permission" : nil, app: "claude-code", message: message))
    }
    let panes = RexInventory.sorted([
        pane("b1", session: "fixture-web", label: "web", folder: "comet", state: .working, message: "Running the test suite"),
        pane("b2", session: "fixture-api", label: "api", folder: "orbit", state: .blocked, message: "Allow running the migration?"),
        pane("b3", session: "fixture-api", label: "api", folder: "orbit-docs", state: .done, message: "Updated three pages"),
        pane("b4", session: "fixture-ops", label: "ops", folder: "deploy", state: .error, message: "Build failed"),
    ])
    let inventory = try JSONEncoder().encode(RexInventory(panes: panes))
    panel.model.rex.reader = { _, next in DispatchQueue.main.async { next(inventory, 1, nil) } }
    panel.model.rex.stopper = {}
    panel.model.rex.focuser = { _, done in done(nil) }
    panel.model.rex.activateRex = {}
    summon()
    func status(_ state: RexState, _ message: String?) -> RexStatus { RexStatus(state: state, app: "claude-code", message: message) }
    let overview = RexOverview(sessions: [
        .init(sessionID: "session:fixture-orbit", label: "orbit", tabs: [
            .init(windowID: "window:orbit-api", label: "api", active: true, focusedBlockID: "block:orbit-agent", panes: [
                .init(blockID: "block:orbit-agent", label: "shell", title: "orbit-api", program: "claude", status: status(.blocked, "Allow running the migration?"), rect: [0, 0, 0.6, 1],
                      preview: ["  Edited db/migrate/0042_add_flights.sql", "", "  Run the migration against the dev database?", "", "  › 1. Yes", "    2. Yes, and don’t ask again for psql", "    3. No, tell Claude what to do differently"]),
                .init(blockID: "block:orbit-logs", label: "logs", title: "server log", program: "tail", status: RexStatus(state: .working), rect: [0.6, 0, 0.4, 0.5],
                      preview: ["GET /flights 200 12ms", "GET /flights/OR42 200 4ms", "POST /bookings 201 31ms", "GET /health 200 1ms"]),
                .init(blockID: "block:orbit-shell", label: "shell", title: "~/orbit", program: "zsh", rect: [0.6, 0.5, 0.4, 0.5],
                      preview: ["~/orbit main ✓", "$ git status --short", " M db/migrate/0042_add_flights.sql", "~/orbit main ✗ $"]),
            ]),
            .init(windowID: "window:orbit-web", label: "web", focusedBlockID: "block:orbit-web", panes: [
                .init(blockID: "block:orbit-web", label: "shell", title: "orbit-web", program: "claude", status: status(.done, "Updated the booking form and its tests"), rect: [0, 0, 1, 1],
                      preview: ["  ✓ Updated src/booking/Form.tsx", "  ✓ Added 6 tests in Form.test.tsx", "", "  All 214 tests pass.", "", "  >"]),
            ]),
        ]),
        .init(sessionID: "session:fixture-comet", label: "comet", tabs: [
            .init(windowID: "window:comet-build", label: "build", active: true, focusedBlockID: "block:comet-cargo", panes: [
                .init(blockID: "block:comet-cargo", label: "shell", title: "cargo build", program: "cargo", status: RexStatus(state: .working, app: "cargo", message: "Compiling comet-core", progress: 64), rect: [0, 0, 1, 0.55],
                      preview: ["   Compiling serde v1.0.219", "   Compiling tokio v1.45.0", "   Compiling comet-net v0.4.2", "   Compiling comet-core v0.9.0", "    Building [=======>    ] 118/184"]),
                .init(blockID: "block:comet-test", label: "shell", title: "~/comet", program: "zsh", rect: [0, 0.55, 1, 0.45],
                      preview: ["~/comet $ just test-watch", "watching 41 files…"]),
            ]),
        ]),
        .init(sessionID: "session:fixture-ops", label: "ops", tabs: [
            .init(windowID: "window:ops-deploy", label: "deploy", active: true, focusedBlockID: "block:ops-deploy", panes: [
                .init(blockID: "block:ops-deploy", label: "shell", title: "deploy staging", program: "terraform", status: RexStatus(state: .error, app: "terraform", message: "Apply failed: quota exceeded"), rect: [0, 0, 1, 1],
                      preview: ["module.cache.aws_elasticache_cluster.main: Creating...", "", "Error: creating ElastiCache Cluster: quota exceeded", "", "  with module.cache.aws_elasticache_cluster.main,", "  on cache/main.tf line 12"]),
            ]),
        ]),
    ])
    let suite = "volant.video.fixture.rex-overview"
    let defaults = UserDefaults(suiteName: suite)!
    defaults.removePersistentDomain(forName: suite)
    let model = RexOverviewModel(previewsAllowed: true, save: { _ in }, defaults: defaults)
    model.focuser = { _, _, done in done(nil) }
    model.activateRex = {}
    model.show(overview)
    let controller = RexOverviewWindowController(model: model)
    let window = controller.window!
    window.setFrame(NSWindow.frameRect(forContentRect: NSRect(x: 0, y: 0, width: 720, height: 560), styleMask: window.styleMask), display: false)
    window.center()
    rexWindow = window
    hooks["rex.show"] = {
        panel.orderOut(nil)
        window.makeKeyAndOrderFront(nil)
        settle(0.4)
    }
    rexController = controller
}

/// Search Menu Items' helper calls, answered with a fictional app's menus.
final class FixtureMenuClient: MenuItemsClient {
    func menuItems(pid: Int32, bundleID: String, completion: @escaping (MenuItemsReply?) -> Void) {
        completion(MenuItemsReply(items: [
            MenuItem(path: ["Quill", "Quit Quill"], shortcut: MenuShortcut(key: "Q", modifiers: 0)),
            MenuItem(path: ["File", "New Draft"], shortcut: MenuShortcut(key: "N", modifiers: 0)),
            MenuItem(path: ["File", "Open Recent", "Harbor Notes.quill"]),
            MenuItem(path: ["File", "Export", "PDF…"], shortcut: MenuShortcut(key: "E", modifiers: MenuShortcut.shift)),
            MenuItem(path: ["File", "Export", "Plain Text…"]),
            MenuItem(path: ["Format", "Make Plain Text"], shortcut: MenuShortcut(key: "T", modifiers: MenuShortcut.shift)),
            MenuItem(path: ["Format", "Font", "Show Fonts"], shortcut: MenuShortcut(key: "T", modifiers: 0)),
            MenuItem(path: ["Format", "Make Rich Text"], enabled: false),
            MenuItem(path: ["View", "Enter Full Screen"], shortcut: MenuShortcut(key: "F", modifiers: MenuShortcut.control)),
        ]))
    }
    func pressMenuItem(pid: Int32, path: [String], bundleID: String, completion: @escaping (MenuPressReply?) -> Void) {
        completion(MenuPressReply(pressed: true))
    }
}

// Search Menu Items, turned on, over a fictional app's menus; no input helper runs.
func menusFixture() {
    freshLauncher()
    summon()
    panel.model.config.searchMenuItems = true
    panel.model.menuItems.client = FixtureMenuClient()
    panel.model.menuItems.pressDelay = 0
    panel.model.menuItems.activate = { _ in }
    panel.model.menuItems.capture(MenuTarget(pid: 4242, bundleID: "com.example.quill", name: "Quill", path: nil))
    settle()
}

/// A color sampler that answers when the video's click lands, with the poster's coral.
final class VideoSampler: ColorSampling {
    var pending: ((PickedColor?) -> Void)?
    func sample(_ completion: @escaping (PickedColor?) -> Void) { pending = completion }
}
let videoSampler = VideoSampler()

// Pick Color with a sampler that answers with the poster's coral; no loupe or screen read.
func colorFixture() {
    freshLauncher()
    panel.model.colorSampler = videoSampler
    summon()
    hooks["color.pick"] = {
        videoSampler.pending?(PickedColor(red: 1, green: 99.0 / 255, blue: 99.0 / 255))
        videoSampler.pending = nil
        waitUntil { panel.isVisible && panel.model.selectedRow?.id == "picked-color:hex" }
        settle(0.3)
    }
}

// Listening servers with fictional listeners and the compiled runtime logos.
func serversFixture() {
    freshLauncher()
    let started = Date().addingTimeInterval(-7200)
    panel.model.servers.loadOverride = { $0([
        ListeningServer(pid: 4101, port: 3000, process: "node", executable: "/opt/fictional/bin/node", directory: "/Users/fictional/site", exposed: false, started: started),
        ListeningServer(pid: 4102, port: 8000, process: "python3.12", executable: "/opt/fictional/bin/python3.12", directory: "/Users/fictional/api", exposed: true, started: Date().addingTimeInterval(-600)),
        ListeningServer(pid: 4105, port: 6379, process: "redis-server", executable: "/opt/fictional/bin/redis-server", directory: nil, exposed: false, started: started),
        ListeningServer(pid: 4106, port: 5432, process: "postgres", executable: "/opt/fictional/bin/postgres", directory: nil, exposed: false, started: started),
        ListeningServer(pid: 4107, port: 8080, process: "java", executable: "/opt/fictional/jdk/bin/java", directory: "/Users/fictional/service", exposed: false, started: started),
    ], nil) }
    summon()
}

// Notes: a fictional notes folder with the note the iPhone capture shows, in the real notes window.
func notesFixture() throws {
    let directory = root.appendingPathComponent("Notes-video")
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let notes: [(String, String)] = [
        ("Trip ideas.md", "# Trip ideas\n\n- Lisbon in spring\n- A cabin weekend up north\n"),
        ("Reading list.md", "# Reading list\n\n- *The Overstory*\n- *Thinking in Systems*\n"),
        ("Design review notes.md", "# Design review notes\n\nThe new tab bar reads well. Keep the search button separate from the tabs.\n"),
        ("Launch checklist.md", "# Launch checklist\n\nEverything to confirm before **version 2.0** ships on Friday.\n\n- [x] Release notes drafted\n- [x] Screenshots for the store page\n- [ ] Final pass on the onboarding copy\n- [ ] Tag the release\n\n```swift\nlet version = \"2.0\"\nprint(\"Shipping \\(version)\")\n```\n\n> Ship when every check is green, not before.\n"),
    ]
    for (offset, (name, text)) in notes.enumerated() {
        let url = directory.appendingPathComponent(name)
        try text.write(to: url, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.modificationDate: Date().addingTimeInterval(Double(offset - notes.count) * 3600)], ofItemAtPath: url.path)
    }
    let store = NotesStore(directory: directory)
    let notesWindow = NotesPanel(store: store)
    notesWindow.setFrameAutosaveName("")
    notesWindow.appearance = app.appearance
    notesWindow.setContentSize(NSSize(width: 600, height: 540))
    notesWindow.open(noteID: "Launch checklist.md")
    notesWindow.model.editing = false
    notesWindow.center()
    settle(0.6)
    notesPanel = notesWindow
}

/// Stands in for the input helper so Settings never launches it or prompts for Accessibility.
final class VideoInputHost: InputHostClient {
    func status(prompt: Bool, completion: @escaping (InputHostStatus?) -> Void) { completion(InputHostStatus(trusted: false, secureInput: false)) }
    func beginSession(completion: @escaping (InputSessionStart?) -> Void) { completion(InputSessionStart(refusal: .notTrusted)) }
    func insert(phrase: String, token: Data, completion: @escaping (InputInsertion?) -> Void) { completion(.refused(.notTrusted)) }
    func endSession(token: Data) {}
    func disconnect() {}
}

/// Fictional usage for Settings › Your Volant, the same seed the Settings preview uses.
func seedFictionalUsage(at url: URL) {
    var db: OpaquePointer?
    guard sqlite3_open(url.path, &db) == SQLITE_OK else { return }
    defer { sqlite3_close(db) }
    sqlite3_exec(db, "CREATE TABLE usage (key TEXT PRIMARY KEY, score REAL NOT NULL, last REAL NOT NULL); CREATE TABLE query_choice (query TEXT PRIMARY KEY, key TEXT NOT NULL, last REAL NOT NULL); CREATE TABLE daily_use (day TEXT PRIMARY KEY, uses INTEGER NOT NULL)", nil, nil, nil)
    let pattern = [12, 18, 0, 22, 31, 9, 0, 14, 27, 35, 19, 24, 6, 0, 0, 17, 21, 29, 33, 15, 11, 0, 26, 38, 30, 22, 18, 25, 19, 8]
    let today = Calendar.current.startOfDay(for: Date())
    for (offset, uses) in pattern.enumerated() where uses > 0 {
        let day = UsageStats.dayKey(Calendar.current.date(byAdding: .day, value: offset - (pattern.count - 1), to: today)!)
        sqlite3_exec(db, "INSERT INTO daily_use VALUES ('\(day)', \(uses))", nil, nil, nil)
    }
    let now = Date().timeIntervalSince1970
    let rows: [(String, Double)] = [("app:/System/Applications/Calculator.app", 9.5), ("app:/Applications/Safari.app", 14), ("app:/System/Applications/Notes.app", 6),
                                    ("app:/System/Applications/Calendar.app", 4.5), ("app:/System/Applications/Music.app", 2), ("core:clipboard", 11), ("core:translate", 5),
                                    ("core:notes", 7.5), ("system-action:lockScreen", 3), ("command:settings", 1.5), ("ext:com.mysticcoders.volant.hello:", 2.5)]
    for (key, score) in rows {
        sqlite3_exec(db, "INSERT INTO usage VALUES ('\(key)', \(score), \(now - 3600))", nil, nil, nil)
    }
}

// Settings › Your Volant with fictional usage, reached by clicking its sidebar row.
func settingsFixture() throws {
    let configURL = root.appendingPathComponent("settings-config.json")
    try Data("{}".utf8).write(to: configURL)
    let usageURL = root.appendingPathComponent("settings-usage.sqlite")
    seedFictionalUsage(at: usageURL)
    let host = VideoInputHost()
    let controller = SettingsWindowController(configURL: configURL, usageURL: usageURL, dictationAccess: DictationTypingAccess(client: host),
                                              menuItemsAccess: MenuItemsAccess(client: host)) {}
    controller.refresh(try JSONDecoder().decode(Preferences.self, from: Data(contentsOf: configURL)), apps: [])
    controller.state.section = .general
    let window = controller.window!
    window.appearance = app.appearance
    window.setFrame(NSWindow.frameRect(forContentRect: NSRect(x: 100, y: 100, width: 760, height: 540), styleMask: window.styleMask), display: true)
    window.center()
    controller.showWindow(nil)
    settle(0.6)
    settings = controller
    hooks["settings.yourVolant"] = { controller.state.section = .yourVolant; settle(0.6) }
    hooks["settings.scrollBottom"] = {
        func scrollViews(_ view: NSView) -> [NSScrollView] { (view as? NSScrollView).map { [$0] } ?? view.subviews.flatMap(scrollViews) }
        for scroll in scrollViews(window.contentView!) where scroll.convert(scroll.bounds, to: nil).minX > 200 {
            guard let document = scroll.documentView else { continue }
            document.scroll(NSPoint(x: 0, y: document.isFlipped ? document.bounds.height : 0))
        }
        settle(0.4)
    }
}

/// Finds the sidebar row for a Settings section in window points by selecting rows until the
/// section follows, then putting the original selection back.
func sidebarPoint(_ section: SettingsSection) -> NSPoint? {
    guard let controller = settings, let window = controller.window else { return nil }
    func tables(_ view: NSView) -> [NSTableView] { (view as? NSTableView).map { [$0] } ?? view.subviews.flatMap(tables) }
    guard let table = tables(window.contentView!).first else { return nil }
    let original = controller.state.section
    defer { controller.state.section = original; settle(0.3) }
    for row in 0..<table.numberOfRows {
        table.selectRowIndexes([row], byExtendingSelection: false)
        settle(0.05)
        if controller.state.section == section {
            let rect = table.convert(table.rect(ofRow: row), to: nil)
            return NSPoint(x: rect.minX + 46, y: rect.midY)
        }
    }
    return nil
}

/// Resolves a cursor anchor to a canvas point through where the stage last drew its window.
func anchorPoint(_ name: String) -> NSPoint {
    let windowPoint: NSPoint
    switch name {
    case "notch":
        guard let notch = focusNotch else { fail("No notch for the cursor") }
        drawNotchPlacement()
        windowPoint = NSPoint(x: notch.frame.width / 2 + 40, y: notch.frame.height / 2)
    case "sidebar:yourVolant":
        guard let point = sidebarPoint(.yourVolant) else { fail("No Your Volant sidebar row") }
        windowPoint = point
    default: fail("Unknown cursor anchor \(name)")
    }
    guard let (window, rect) = placement else { fail("No placement for anchor \(name)") }
    let scale = rect.width / window.frame.width
    return NSPoint(x: rect.minX + windowPoint.x * scale, y: rect.minY + windowPoint.y * scale)
}

/// Records where the notch panel is drawn without writing a frame.
func drawNotchPlacement() {
    guard let notch = focusNotch else { return }
    let size = NSSize(width: notch.frame.width * notchScale, height: notch.frame.height * notchScale)
    placement = (notch, NSRect(x: canvasSize / 2 - size.width / 2, y: 1010 - size.height, width: size.width, height: size.height))
}

// MARK: - Running scenes

/// The window that receives keys on the current stage.
func keyWindow() -> NSWindow {
    switch stage {
    case "rex-overview": return rexWindow!
    case "notes", "notes-iphone": return notesPanel!
    case "settings": return settings!.window!
    default: return panel
    }
}

/// Runs one step: its action first, then the frames that show it.
func run(_ step: Step) {
    for _ in 0..<(step.repeat ?? 1) {
        let notchBefore = focusNotch?.frame.size
        if let text = step.type {
            let keyMs = step.keyMs ?? 90
            for (offset, character) in text.enumerated() {
                switch step.into ?? "search" {
                case "form": panel.model.entryForm?.name.append(character)
                case "chat": panel.model.acp.draft.append(character)
                case "catalog": panel.model.catalog.input.append(character)
                default: panel.model.query.append(character)
                }
                settle(0.12)
                caretToEnd()
                emit(offset == text.count - 1 ? (step.holdMs ?? 600) : keyMs)
            }
            continue
        }
        if let key = step.key {
            sendKey(key, to: keyWindow())
            if step.stage == "rex-overview" && stage != "rex-overview" { hooks["rex.show"]?() }
        }
        if let target = step.cursor {
            let destination: NSPoint
            switch target {
            case .anchor(let name): destination = anchorPoint(name)
            case .point(let x, let y): destination = NSPoint(x: x, y: y)
            }
            let start = cursorPoint ?? destination
            let moveMs = step.moveMs ?? 500
            let count = max(1, moveMs / 40)
            for index in 1...count {
                let t = Double(index) / Double(count)
                let eased = t < 0.5 ? 2 * t * t : 1 - pow(-2 * t + 2, 2) / 2
                cursorPoint = NSPoint(x: start.x + (destination.x - start.x) * eased, y: start.y + (destination.y - start.y) * eased)
                if count > 1 || moveMs > 1 { emit(moveMs / count) }
            }
        }
        if step.click == true {
            cursorPressed = true
            emit(140)
            cursorPressed = false
        }
        if let hook = step.hook {
            guard let action = hooks[hook] else { fail("Unknown hook \(hook)") }
            action()
        }
        if let next = step.stage { stage = next }
        if step.hideCursor == true { cursorPoint = nil }
        if let reveal = step.reveal, let from = notchBefore {
            settle(0.7)
            let count = max(1, reveal / 40)
            for index in 1...count {
                let t = Double(index) / Double(count)
                notchReveal = (from, CGFloat(1 - pow(1 - t, 3)))
                emit(reveal / count)
            }
            notchReveal = nil
        }
        if let hold = step.holdMs { settle(0.05); emit(hold) }
    }
}

let fixtures: [String: () throws -> Void] = [
    "focus": focusFixture, "breaks": breaksFixture, "catalog": catalogFixture, "chat": chatFixture, "rex": rexFixture,
    "menus": menusFixture, "color": colorFixture, "servers": serversFixture, "notes": notesFixture, "settings": settingsFixture,
]

app.activate(ignoringOtherApps: true)
for scene in sceneList.scenes where onlyScenes?.contains(scene.number) ?? true {
    currentScene = scene.number
    frameNumber = 0
    hooks = [:]
    cursorPoint = nil
    stage = "launcher"
    stageCaption = nil
    guard let fixture = fixtures[scene.fixture] else { fail("Unknown fixture \(scene.fixture)") }
    try fixture()
    titleCard(scene, ms: sceneList.cardMs)
    stageCaption = (filled(scene.caption), scene.note.map(filled))
    for step in scene.steps { run(step) }
    panel?.orderOut(nil)
    focusNotch?.orderOut(nil); focusNotch = nil
    breakPresenter?.close(); breakPresenter = nil
    rexWindow?.orderOut(nil)
    notesPanel?.orderOut(nil)
    settings?.window?.orderOut(nil)
    print("Rendered scene \(scene.number): \(scene.title), \(frameNumber) frames")
}
if onlyScenes == nil || onlyScenes?.contains(0) == true {
    currentScene = 0
    frameNumber = 0
    stage = "end"
    stageCaption = nil
    cursorPoint = nil
    emit(sceneList.endMs)
    print("Rendered the end card")
}
positions.removePersistentDomain(forName: "volant.video.fixture")
exit(0)
