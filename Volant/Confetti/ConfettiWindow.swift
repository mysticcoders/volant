import AppKit
import QuartzCore

/// A brief burst of confetti over whatever is on screen. Deliberately inert: the window ignores
/// mouse events, never becomes key or main, and closes itself, so it cannot steal focus, swallow a
/// click, or outlive its welcome if the launcher is dismissed underneath it.
final class ConfettiWindow: NSWindow {
    /// How long new confetti is emitted, and how long the last pieces get to fall afterwards.
    static let emitDuration: TimeInterval = 1.2
    static let settleDuration: TimeInterval = 2.6

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
        let emitter = Self.emitter(width: frame.width)
        layer.addSublayer(emitter)
        orderFrontRegardless()

        // Stop making new confetti, then let what is already falling finish before closing.
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.emitDuration) { [weak emitter] in
            emitter?.birthRate = 0
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

    /// Emits from just above the top edge so pieces fall into view rather than appearing mid-air.
    static func emitter(width: CGFloat) -> CAEmitterLayer {
        let emitter = CAEmitterLayer()
        emitter.emitterShape = .line
        emitter.emitterPosition = CGPoint(x: width / 2, y: 12)
        emitter.emitterSize = CGSize(width: width, height: 1)
        emitter.renderMode = .additive
        emitter.emitterCells = cells()
        return emitter
    }

    static func cells() -> [CAEmitterCell] {
        colors.map { color in
            let cell = CAEmitterCell()
            cell.contents = piece(color: color).cgImage(forProposedRect: nil, context: nil, hints: nil)
            cell.birthRate = 14
            cell.lifetime = Float(settleDuration)
            cell.velocity = 180
            cell.velocityRange = 90
            // The layer is flipped relative to the screen, so a positive Y sends pieces downward.
            cell.emissionLongitude = .pi
            cell.emissionRange = .pi / 6
            cell.spin = 3
            cell.spinRange = 4
            cell.scale = 0.5
            cell.scaleRange = 0.3
            cell.yAcceleration = 90
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
