import AppKit
import VolantCore

/// Samples one color from the screen. Tests supply a fake so no real magnifier appears.
protocol ColorSampling {
    /// Calls back on the main thread with the chosen color, or nil when the owner pressed Escape.
    func sample(_ completion: @escaping (PickedColor?) -> Void)
}

/// macOS's own magnifying loupe, `NSColorSampler`. It needs no permission: the system draws the
/// loupe and hands back only the single color the owner clicks, never a screenshot.
final class ScreenColorSampler: ColorSampling {
    private var sampler: NSColorSampler?

    func sample(_ completion: @escaping (PickedColor?) -> Void) {
        let sampler = NSColorSampler()
        self.sampler = sampler
        sampler.show { [weak self] color in
            let picked = color.flatMap(Self.picked)
            DispatchQueue.main.async {
                self?.sampler = nil
                completion(picked)
            }
        }
    }

    /// The sampled color in sRGB, the space CSS values are written in.
    static func picked(_ color: NSColor) -> PickedColor? {
        guard let srgb = color.usingColorSpace(.sRGB) else { return nil }
        return PickedColor(red: Double(srgb.redComponent), green: Double(srgb.greenComponent), blue: Double(srgb.blueComponent))
    }
}
