import AppKit

/// Screen-space placement, independent of windows so multi-display geometry stays testable.
struct LauncherSnapPlacement {
    let frame: NSRect
    let vertical: CGFloat?
    let horizontal: CGFloat?

    static func resolve(_ frame: NSRect, in screen: NSRect, threshold: CGFloat = 12, margin: CGFloat = 20) -> Self {
        func closest(_ pairs: [(origin: CGFloat, guide: CGFloat)], to value: CGFloat) -> (CGFloat, CGFloat)? {
            pairs.filter { abs($0.origin - value) <= threshold }
                .min { abs($0.origin - value) < abs($1.origin - value) }
                .map { ($0.origin, $0.guide) }
        }
        var xs: [(CGFloat, CGFloat)] = [], ys: [(CGFloat, CGFloat)] = []
        if frame.width <= screen.width {
            xs.append((screen.midX - frame.width / 2, screen.midX))
            if frame.width + margin * 2 <= screen.width {
                xs += [(screen.minX + margin, screen.minX + margin), (screen.maxX - margin - frame.width, screen.maxX - margin)]
            }
        }
        if frame.height <= screen.height {
            ys.append((screen.midY - frame.height / 2, screen.midY))
            if frame.height + margin * 2 <= screen.height {
                ys += [(screen.minY + margin, screen.minY + margin), (screen.maxY - margin - frame.height, screen.maxY - margin)]
            }
        }
        let x = closest(xs, to: frame.minX), y = closest(ys, to: frame.minY)
        return Self(frame: NSRect(x: x?.0 ?? frame.minX, y: y?.0 ?? frame.minY, width: frame.width, height: frame.height),
                    vertical: x?.1, horizontal: y?.1)
    }
}

/// A mouse-transparent child panel never takes keyboard focus away from the launcher.
final class LauncherSnapGuides {
    private var overlay: NSPanel?
    var isVisible: Bool { overlay?.isVisible == true }

    func show(_ placement: LauncherSnapPlacement, screen: NSRect, above parent: NSWindow) {
        guard placement.vertical != nil || placement.horizontal != nil else { hide(); return }
        let panel: NSPanel
        if let overlay { panel = overlay }
        else {
            panel = SnapGuidePanel(contentRect: screen, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
            panel.title = "Volant Alignment Guides"
            panel.isOpaque = false
            panel.backgroundColor = .clear
            panel.hasShadow = false
            panel.ignoresMouseEvents = true
            panel.isReleasedWhenClosed = false
            panel.hidesOnDeactivate = false
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
            panel.contentView = SnapGuideView(frame: NSRect(origin: .zero, size: screen.size))
            overlay = panel
        }
        panel.appearance = parent.effectiveAppearance
        panel.setFrame(screen, display: false)
        if let view = panel.contentView as? SnapGuideView {
            view.vertical = placement.vertical.map { $0 - screen.minX }
            view.horizontal = placement.horizontal.map { $0 - screen.minY }
            view.exclusion = placement.frame.offsetBy(dx: -screen.minX, dy: -screen.minY)
            view.needsDisplay = true
        }
        if panel.parent !== parent {
            panel.parent?.removeChildWindow(panel)
            parent.addChildWindow(panel, ordered: .above)
        }
        panel.orderFront(nil)
    }

    func hide() {
        guard let overlay else { return }
        overlay.parent?.removeChildWindow(overlay)
        overlay.orderOut(nil)
    }
}

private final class SnapGuidePanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

final class SnapGuideView: NSView {
    var vertical: CGFloat?
    var horizontal: CGFloat?
    var exclusion = NSRect.zero
    override var isOpaque: Bool { false }
    override func draw(_ dirtyRect: NSRect) {
        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }
        // Guides stop outside the launcher rather than crossing text and controls.
        let clip = NSBezierPath(rect: bounds)
        clip.appendRect(exclusion.insetBy(dx: -6, dy: -6))
        clip.windingRule = .evenOdd
        clip.addClip()
        let path = NSBezierPath()
        if let vertical {
            path.move(to: NSPoint(x: vertical, y: bounds.minY))
            path.line(to: NSPoint(x: vertical, y: bounds.maxY))
        }
        if let horizontal {
            path.move(to: NSPoint(x: bounds.minX, y: horizontal))
            path.line(to: NSPoint(x: bounds.maxX, y: horizontal))
        }
        path.lineWidth = 4
        NSColor.windowBackgroundColor.withAlphaComponent(0.9).setStroke()
        path.stroke()
        path.lineWidth = 1.5
        path.setLineDash([5, 4], count: 2, phase: 0)
        (NSColor(named: "AccentColor") ?? NSColor.controlAccentColor).setStroke()
        path.stroke()
    }
}
