import AppKit

/// Per-app hotkeys: press once to activate or launch, press again while frontmost to hide.
enum AppHotKeys {
    @discardableResult
    static func register(_ entries: [AppHotKey]) -> [String] {
        var failures: [String] = []
        for entry in entries {
            guard let combo = KeyCombo(parsing: entry.hotKey) else { failures.append("Invalid shortcut for " + entry.bundleIdentifier); continue }
            let bundleID = entry.bundleIdentifier
            if HotKeyCenter.shared.register(combo, handler: { toggle(bundleID) }) == nil {
                failures.append("Shortcut unavailable: " + entry.hotKey + " (" + bundleID + ")")
            }
        }
        return failures
    }

    static func toggle(_ bundleID: String) {
        let running = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first
        if let running {
            if running.isActive {
                running.hide()
            } else {
                running.activate()
            }
            return
        }
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return }
        NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
    }
}
