# Launcher positioning

Drag the wing in the search header to move Volant. The position is saved by native move notifications and recovered into a visible display when screen arrangements change.

Snap guides align the launcher to the usable screen center and edges with a 20-point inset and a 12-point capture distance. Each axis resolves independently against the display containing the pointer; screen coordinates may be negative. Hold Option during a drag to bypass both snapping and guides. An oversized launcher does not snap along an axis it cannot fit. Saved placement remains the actual final frame.

Guides use a mouse-transparent, non-key child panel and the shared AccentColor asset, with a native accent fallback in asset-free fixtures. Dashed lines have a semantic window-background halo for contrast and stop outside the launcher so text/controls remain readable. Releasing the wing, moving outside capture range, using Option, or dismissing the launcher clears the overlay. No AeroSpace configuration changes are needed.

Local evidence: Release build and focused SwiftLint passed. Native launcher fixtures passed in light/dark, including geometry on a fictional negative-origin screen, center/edge placement, oversized windows, free positioning, retained keyboard focus, guide cleanup, and native wing mouse-down/drag/up handling. The actual guide view was rendered around the native launcher in light/dark and inspected for contrast and control occlusion. The snap preview retains a fictional busy state solely to survive computer-use focus shifts; it never starts networking. Ordinary focus-loss behavior is separately covered by the launcher suite.

Automated CI selects UI checks for these Panel/fixture changes and uploads the guide images. Live pointer dragging across multiple physical displays, installed-app verification and refreshed notarized distribution remain separate evidence. A successful build or render does not establish them.
