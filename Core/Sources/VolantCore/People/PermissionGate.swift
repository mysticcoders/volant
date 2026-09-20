import Foundation

/// Tracks in-flight system permission prompts so the panel does not dismiss itself when the prompt takes focus.
public enum PermissionGate {
    private(set) static var pending = 0
    public static func begin() { pending += 1 }
    public static func end() { pending = max(0, pending - 1) }
    public static var isPrompting: Bool { pending > 0 }
}
