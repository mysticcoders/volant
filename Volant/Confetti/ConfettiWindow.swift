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

    /// Cannons along the bottom edge, fired up and inward. Gravity arcs the pieces over and brings
    /// them back down, which is what throwing confetti looks like; emitting from the top and
    /// letting it fall is snow.
    ///
    /// The layer is not flipped, so on macOS +y points up the screen: launch velocity is positive
    /// and `yAcceleration` is negative.
    static let gravity: CGFloat = -2000

    /// Launch speed is derived from the screen rather than fixed, so the burst fills a display of
    /// any height instead of dying in the corners. From v = sqrt(2gh), with headroom so the
    /// fastest pieces carry past the top edge rather than stalling just below it.
    static func launchSpeed(forHeight height: CGFloat) -> CGFloat {
        sqrt(2 * abs(gravity) * max(height, 1) * 1.15)
    }

    /// Peak of a vertical launch, v² / 2g.
    static func peakHeight(forHeight height: CGFloat) -> CGFloat {
        let speed = launchSpeed(forHeight: height)
        return (speed * speed) / (2 * abs(gravity))
    }

    /// Five cannons rather than two: corners alone read as a pair of hoses, while spreading the
    /// sources across the bottom edge fills the width.
    static func emitters(size: CGSize) -> [CAEmitterLayer] {
        let speed = launchSpeed(forHeight: size.height)
        let positions: [CGFloat] = [0, 0.25, 0.5, 0.75, 1]
        return positions.map { fraction in
            let emitter = CAEmitterLayer()
            emitter.emitterShape = .point
            emitter.emitterPosition = CGPoint(x: size.width * fraction, y: 0)
            emitter.emitterSize = .zero
            // Angles run counterclockwise from +x, so an angle below .pi/2 leans right and above it
            // leans left. Each cannon aims towards the far side of the screen; the middle one fires
            // straight up. Getting this backwards aims the corner cannons off-screen.
            let lean = (fraction - 0.5) * (.pi / 5)
            emitter.emitterCells = cells(angle: .pi / 2 + lean, speed: speed)
            return emitter
        }
    }

    static func cells(angle: CGFloat, speed: CGFloat) -> [CAEmitterCell] {
        colors.map { color in
            let cell = CAEmitterCell()
            cell.contents = piece(color: color).cgImage(forProposedRect: nil, context: nil, hints: nil)
            cell.birthRate = 160
            cell.lifetime = Float(settleDuration)
            cell.velocity = speed
            // A wide spread of speeds is what fills the middle of the screen rather than leaving a
            // band of confetti all at the same height.
            cell.velocityRange = speed * 0.55
            cell.emissionLongitude = angle
            cell.emissionRange = .pi / 3
            cell.yAcceleration = gravity
            cell.spin = 3
            cell.spinRange = 6
            cell.scale = 0.5
            cell.scaleRange = 0.3
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
