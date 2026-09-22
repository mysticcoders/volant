import AppKit
import QuartzCore

/// A brief burst of confetti over whatever is on screen. Deliberately inert: the window ignores
/// mouse events, never becomes key or main, and closes itself, so it cannot steal focus, swallow a
/// click, or outlive its welcome if the launcher is dismissed underneath it.
final class ConfettiWindow: NSWindow {
    /// How long new confetti is emitted, and how long the last pieces get to fall afterwards.
    static let emitDuration: TimeInterval = 0.35
    static let settleDuration: TimeInterval = 3.2

    private var dismissal: DispatchWorkItem?

    static func celebrate(on screen: NSScreen? = nil) {
        let target = screen ?? NSScreen.screens.first { $0.frame.contains(NSEvent.mouseLocation) } ?? NSScreen.main
        guard let target else { return }
        let window = ConfettiWindow(screen: target)
        window.start()
    }

    private init(screen: NSScreen) {
        super.init(contentRect: screen.frame, styleMask: .borderless, backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        ignoresMouseEvents = true
        // Above ordinary windows but below the screen saver, and present on every Space so it does
        // not drag the owner back to the Space it was triggered from.
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        isReleasedWhenClosed = false
        setFrame(screen.frame, display: false)

        let view = NSView(frame: NSRect(origin: .zero, size: screen.frame.size))
        view.wantsLayer = true
        contentView = view
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    private func start() {
        guard let layer = contentView?.layer else { return }
        let emitters = Self.emitters(width: frame.width)
        emitters.forEach(layer.addSublayer)
        orderFrontRegardless()

        // A throw is a burst, not a stream: stop emitting quickly, then let the arc play out.
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.emitDuration) {
            emitters.forEach { $0.birthRate = 0 }
        }
        let dismissal = DispatchWorkItem { [weak self] in self?.finish() }
        self.dismissal = dismissal
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.emitDuration + Self.settleDuration, execute: dismissal)
    }

    private func finish() {
        dismissal?.cancel()
        dismissal = nil
        orderOut(nil)
        close()
    }

    /// Two cannons at the bottom corners, fired up and inward. Gravity arcs the pieces over and
    /// brings them back down, which is what throwing confetti looks like; emitting from the top
    /// and letting it fall is snow.
    ///
    /// The layer is not flipped, so on macOS +y points up the screen: the launch velocity is
    /// positive and `yAcceleration` is negative.
    static let launchSpeed: CGFloat = 620
    static let gravity: CGFloat = -820

    /// How high a piece launched straight up reaches before falling back, from v² / 2g. Used to
    /// keep the burst tall enough to read as a throw rather than a fizzle.
    static var peakHeight: CGFloat { (launchSpeed * launchSpeed) / (2 * abs(gravity)) }

    static func emitters(width: CGFloat) -> [CAEmitterLayer] {
        // Angles measured from +x, so just past vertical and leaning towards the far corner.
        [(CGPoint(x: 0, y: 0), CGFloat.pi / 2 - .pi / 7),
         (CGPoint(x: width, y: 0), CGFloat.pi / 2 + .pi / 7)].map { origin, angle in
            let emitter = CAEmitterLayer()
            emitter.emitterShape = .point
            emitter.emitterPosition = origin
            emitter.emitterSize = .zero
            emitter.emitterCells = cells(angle: angle)
            return emitter
        }
    }

    static func cells(angle: CGFloat) -> [CAEmitterCell] {
        colors.map { color in
            let cell = CAEmitterCell()
            cell.contents = piece(color: color).cgImage(forProposedRect: nil, context: nil, hints: nil)
            cell.birthRate = 90
            cell.lifetime = Float(settleDuration)
            cell.velocity = launchSpeed
            cell.velocityRange = launchSpeed * 0.35
            cell.emissionLongitude = angle
            cell.emissionRange = .pi / 5
            cell.yAcceleration = gravity
            cell.spin = 3
            cell.spinRange = 5
            cell.scale = 0.5
            cell.scaleRange = 0.3
            // Stay solid through the arc and fade only as the pieces land.
            cell.alphaSpeed = -1 / Float(settleDuration)
            return cell
        }
    }

    static let colors: [NSColor] = [
        .systemPink, .systemOrange, .systemYellow, .systemGreen, .systemBlue, .systemPurple, .systemTeal,
    ]

    private static func piece(color: NSColor) -> NSImage {
        let size = NSSize(width: 9, height: 14)
        let image = NSImage(size: size)
        image.lockFocus()
        color.setFill()
        NSBezierPath(roundedRect: NSRect(origin: .zero, size: size), xRadius: 2, yRadius: 2).fill()
        image.unlockFocus()
        return image
    }
}
