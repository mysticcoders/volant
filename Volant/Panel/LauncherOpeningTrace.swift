import Foundation
import OSLog

/// Fixed metadata only: never include queries, results, app paths, or draft text.
enum LauncherOpenSource: String { case hotkey, workspace, menu, other }

final class LauncherOpeningTrace {
    private static let log = OSLog(subsystem: "com.mysticcoders.volant", category: "Opening")
    private let id = OSSignpostID(log: LauncherOpeningTrace.log)
    private let source: LauncherOpenSource
    private let started: TimeInterval
    private var finished = false

    init(source: LauncherOpenSource, started: TimeInterval) {
        self.source = source
        self.started = started
        os_signpost(.begin, log: Self.log, name: "Summon", signpostID: id, "source=%{public}@", source.rawValue)
    }

    /// Monotonic duration; the unified log supplies the corresponding wall timestamp.
    /// Ready means a key window and native text editor, not a presented screen frame.
    func finish(ready: Bool) {
        guard !finished else { return }
        finished = true
        let milliseconds = (ProcessInfo.processInfo.systemUptime - started) * 1000
        os_signpost(.end, log: Self.log, name: "Summon", signpostID: id,
                    "source=%{public}@ ready=%{public}d elapsed_ms=%{public}.3f", source.rawValue, ready ? 1 : 0, milliseconds)
    }
}
