import CoreGraphics
import Foundation

/// Prints the on-screen windows of the named app from the window server, one per line as
/// "layer width x height title", so visibility checks do not depend on accessibility.
let owner = CommandLine.arguments.dropFirst().first ?? "Volant"
let info = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
for window in info where window[kCGWindowOwnerName as String] as? String == owner {
    let alpha = window[kCGWindowAlpha as String] as? Double ?? 0
    guard alpha > 0, let bounds = window[kCGWindowBounds as String] as? [String: Double] else { continue }
    let layer = window[kCGWindowLayer as String] as? Int ?? 0
    let title = window[kCGWindowName as String] as? String ?? ""
    print("\(layer) \(Int(bounds["Width"] ?? 0))x\(Int(bounds["Height"] ?? 0)) \(title)")
}
