import AppKit
import OSLog
import VolantCore

/// Per-app hotkeys: press once to activate or launch, press again while frontmost to hide.
enum AppHotKeys {
    private static let logger = Logger(subsystem: "com.mysticcoders.volant", category: "AppShortcuts")

    @discardableResult
    static func register(_ entries: [AppHotKey], onFailure: @escaping (String) -> Void = { _ in }) -> [String] {
        var failures: [String] = []
        for entry in entries {
            guard let combo = KeyCombo(parsing: entry.hotKey) else { failures.append("Invalid shortcut for " + entry.bundleIdentifier); continue }
            let bundleID = entry.bundleIdentifier
            if HotKeyCenter.shared.register(combo, handler: {
                toggle(bundleID) { message in onFailure(bundleID + ": " + message) }
            }) == nil {
                failures.append("Shortcut unavailable: " + KeyCombo.display(entry.hotKey) + " (" + bundleID + ")")
            }
        }
        return failures
    }

    static func toggle(_ bundleID: String, onFailure: @escaping (String) -> Void = { _ in }) {
        let running = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first
        logger.notice("App shortcut delivered; running=\(running != nil), active=\(running?.isActive == true)")
        perform(isActive: running?.isActive == true, hide: { running?.hide() == true }, applicationURL: {
            running?.bundleURL ?? NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID)
        }, open: { url, completion in
            // Launch Services also sends reopen to an existing process, restoring its windows.
            // activate() alone can leave a running app invisible and silently reject focus.
            let configuration = NSWorkspace.OpenConfiguration()
            configuration.activates = true
            configuration.hides = false
            NSWorkspace.shared.openApplication(at: url, configuration: configuration) { application, error in
                DispatchQueue.main.async {
                    completion(application != nil && error == nil)
                }
            }
        }, onFailure: { message in
            logger.error("App shortcut failed: \(message, privacy: .public)")
            NSSound.beep()
            onFailure(message)
        })
    }

    /// Keep OS handoff injectable: logic tests must never launch or hide the owner's apps.
    static func perform(isActive: Bool, hide: () -> Bool, applicationURL: () -> URL?,
                        open: (URL, @escaping (Bool) -> Void) -> Void, onFailure: @escaping (String) -> Void) {
        if isActive {
            if !hide() { onFailure("macOS could not hide the application.") }
            return
        }
        guard let url = applicationURL() else {
            onFailure("Application not found. Check its shortcut in Settings.")
            return
        }
        open(url) { succeeded in
            if !succeeded { onFailure("macOS could not open the application. Try opening it from Finder.") }
        }
    }
}
