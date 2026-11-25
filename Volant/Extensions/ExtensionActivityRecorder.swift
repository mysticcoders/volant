import Foundation
import VolantCore

/// Volant's in-memory extension activity, shared by every `ExtensionManager` and shown in Settings ›
/// Extensions › Activity (#68). Used on the main thread only. Nothing is written to disk, so it lasts
/// until Volant quits; the owner may export it to a file they choose.
final class ExtensionActivityRecorder: ObservableObject {
    static let shared = ExtensionActivityRecorder()
    @Published private(set) var log: ExtensionActivityLog

    init(capacity: Int = ExtensionActivityLog.defaultCapacity) { log = ExtensionActivityLog(capacity: capacity) }

    func record(_ event: ExtensionActivity) { log.record(event) }
    func clear() { log.clear() }
}
