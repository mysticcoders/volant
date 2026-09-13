import Foundation

/// Tracks in-flight system permission prompts so the panel does not dismiss itself when the prompt takes focus.
enum PermissionGate {
    private(set) static var pending = 0
    static func begin() { pending += 1 }
    static func end() { pending = max(0, pending - 1) }
    static var isPrompting: Bool { pending > 0 }
}
