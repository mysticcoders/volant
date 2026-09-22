import AppKit
import QuartzCore

/// A brief burst of confetti over whatever is on screen. Deliberately inert: the window ignores
/// mouse events, never becomes key or main, and closes itself, so it cannot steal focus, swallow a
/// click, or outlive its welcome if the launcher is dismissed underneath it.
final class ConfettiWindow: NSWindow {
    /// How long new confetti is emitted, and how long the last pieces get to fall afterwards.
    static let emitDuration: TimeInterval = 0.25
    static let settleDuration: TimeInterval = 4.2

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
        let emitters = Self.emitters(size: frame.size)
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

    /// Two cannons, one in each bottom corner, like party poppers fired up and across the screen.
    /// Each sprays a cone, so the burst fans out as a triangle from its corner, then gravity arcs
    /// the pieces over and brings them back down through the bottom edge. It is a plain ballistic
    /// arc: CAEmitterCell has no air drag, so there is no flutter at the end.
    ///
    /// The layer is not flipped, so on macOS +y points up the screen: launch velocity is positive
    /// and `yAcceleration` is negative. Angles run counterclockwise from +x.
    static let gravity: CGFloat = -2000

    /// Width of the spray cone. Each cannon's aim is capped so that even a piece at the edge of the
    /// cone stays below vertical, so nothing fires backwards off the screen from a corner.
    static let sprayCone: CGFloat = .pi / 6

    /// How high the burst reaches, as a fraction of the screen, along the aim direction.
    static let peakFraction: CGFloat = 0.7

    /// Roughly how many pieces the whole burst throws, across both cannons and every colour. This
    /// is the dial worth turning: birth rate is derived from it.
    static let pieceCount = 120

    static let cannonCount = 2

    static func birthRate(cannons: Int) -> Float {
        let cells = Double(max(cannons, 1) * colors.count)
        return Float(Double(pieceCount) / (emitDuration * cells))
    }

    /// What the burst actually throws, for the parameters in use.
    static func totalPieces(cannons: Int) -> Int {
        Int((Double(birthRate(cannons: cannons)) * emitDuration * Double(cannons * colors.count)).rounded())
    }

    /// Elevation of each cannon's aim, from the horizontal, chosen so the arc peaks over the middle
    /// of the screen and the two sprays cross there. For a peak height H the apex sits 2H/tan(aim)
    /// in from the corner, so aiming at the centre means tan(aim) = 4H / width.
    static func aimElevation(for size: CGSize) -> CGFloat {
        let height = max(size.height, 1) * peakFraction
        let ideal = atan(4 * height / max(size.width, 1))
        let steepestSafe = .pi / 2 - sprayCone - .pi / 90
        return min(ideal, steepestSafe)
    }

    /// Launch speed from the screen, so the arc scales with the display. The vertical part of the
    /// launch, v·sin(aim), has to reach `peakFraction` of the height: v·sin(aim) = sqrt(2gh).
    static func launchSpeed(for size: CGSize) -> CGFloat {
        sqrt(2 * abs(gravity) * max(size.height, 1) * peakFraction) / sin(aimElevation(for: size))
    }

    /// Peak of a piece fired exactly along the aim, (v·sin(aim))² / 2g.
    static func peakHeight(for size: CGSize) -> CGFloat {
        let vertical = launchSpeed(for: size) * sin(aimElevation(for: size))
        return (vertical * vertical) / (2 * abs(gravity))
    }

    /// How far in from its corner a piece fired along the aim reaches its apex.
    static func apexDistance(for size: CGSize) -> CGFloat {
        let speed = launchSpeed(for: size), aim = aimElevation(for: size)
        return speed * speed * sin(aim) * cos(aim) / abs(gravity)
    }

    /// Longest time any piece spends in the air: the fastest piece at the steepest angle in the
    /// cone, up and back down to the bottom edge.
    static func longestFlight(for size: CGSize) -> TimeInterval {
        let fastest = launchSpeed(for: size) * (1 + speedSpread)
        let steepest = min(aimElevation(for: size) + sprayCone, .pi / 2)
        return TimeInterval(2 * fastest * sin(steepest) / abs(gravity))
    }

    /// Speeds vary this much either side of the launch speed, so some pieces fall short and some
    /// carry further across the screen.
    static let speedSpread: CGFloat = 0.25

    static func emitters(size: CGSize) -> [CAEmitterLayer] {
        let speed = launchSpeed(for: size)
        let aim = aimElevation(for: size)
        let rate = birthRate(cannons: cannonCount)
        // Left corner aims up and right; right corner is its mirror, up and left.
        let cannons: [(CGPoint, CGFloat)] = [
            (CGPoint(x: 0, y: 0), aim),
            (CGPoint(x: size.width, y: 0), .pi - aim),
        ]
        return cannons.map { origin, angle in
            let emitter = CAEmitterLayer()
            emitter.emitterShape = .point
            emitter.emitterPosition = origin
            emitter.emitterSize = .zero
            emitter.emitterCells = cells(angle: angle, speed: speed, birthRate: rate)
            return emitter
        }
    }

    static func cells(angle: CGFloat, speed: CGFloat, birthRate: Float) -> [CAEmitterCell] {
        colors.map { color in
            let cell = CAEmitterCell()
            cell.contents = piece(color: color).cgImage(forProposedRect: nil, context: nil, hints: nil)
            cell.birthRate = birthRate
            cell.lifetime = Float(settleDuration)
            cell.velocity = speed
            cell.velocityRange = speed * speedSpread
            cell.emissionLongitude = angle
            cell.emissionRange = sprayCone
            cell.yAcceleration = gravity
            cell.spin = 3
            cell.spinRange = 6
            cell.scale = 0.5
            cell.scaleRange = 0.3
            // Paper does not fade in the air. Pieces leave through the bottom edge before their
            // lifetime ends, so they are simply gone rather than dissolving mid-fall.
            cell.alphaSpeed = 0
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
