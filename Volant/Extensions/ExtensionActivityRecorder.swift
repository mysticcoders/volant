import Foundation
import VolantCore

/// Volant's in-memory extension activity, shared by every `ExtensionManager`, for an Activity history in
/// Settings (#68). Used on the main thread only. Nothing is written to disk, so it lasts until Volant quits.
final class ExtensionActivityRecorder {
    static let shared = ExtensionActivityRecorder()
    private(set) var log: ExtensionActivityLog

    init(capacity: Int = ExtensionActivityLog.defaultCapacity) { log = ExtensionActivityLog(capacity: capacity) }

    func record(_ event: ExtensionActivity) { log.record(event) }
    func clear() { log.clear() }
}
