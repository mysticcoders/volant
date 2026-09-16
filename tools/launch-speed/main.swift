// Opt-in installed-app opening benchmark. No key logging or screen capture.
import AppKit
import Darwin

let application = NSApplication.shared
application.setActivationPolicy(.prohibited)
let bundleID = "com.mysticcoders.volant"
func visible(_ pid: pid_t) -> Bool {
    let windows = CGWindowListCopyWindowInfo(.optionOnScreenOnly, kCGNullWindowID) as? [[String: Any]] ?? []
    return windows.contains { window in
        guard (window[kCGWindowOwnerPID as String] as? Int) == Int(pid),
              (window[kCGWindowLayer as String] as? Int) == Int(NSWindow.Level.floating.rawValue),
              let bounds = window[kCGWindowBounds as String] as? [String: CGFloat],
              (bounds["Width"] ?? 0) >= 550, (bounds["Height"] ?? 0) >= 250,
              abs((bounds["Width"] ?? 0) / (bounds["Height"] ?? 1) - 750.0 / 480.0) < 0.03 else { return false }
        return (window[kCGWindowAlpha as String] as? Double ?? 1) > 0
    }
}
setbuf(stdout, nil)
let mode = CommandLine.arguments.dropFirst().first ?? "reopen"
guard ["reopen", "startup"].contains(mode) else {
    fputs("Use reopen or startup mode.\n", stderr); exit(2)
}
func require(_ condition: @autoclosure () -> Bool, _ message: String) {
    guard condition() else { fputs(message + "\n", stderr); exit(5) }
}
print("mode,sample,request_to_window_server_visible_ms")
    func pump(_ seconds: Double) { RunLoop.main.run(until: Date().addingTimeInterval(seconds)) }
    let count = mode == "startup" ? 5 : 20
    for trial in 1...count {
        guard let current = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first else {
            fputs("Expected Volant to be running before each trial.\n", stderr); exit(3)
        }
        if mode == "startup" {
            require(current.terminate(), "Clean quit request failed")
            let deadline = Date().addingTimeInterval(10)
            while !current.isTerminated && Date() < deadline { pump(0.01) }
            require(current.isTerminated, "Refusing to force quit Volant")
        } else {
            _ = current.hide()
            let deadline = Date().addingTimeInterval(3)
            while visible(current.processIdentifier) && Date() < deadline { pump(0.01) }
            guard !visible(current.processIdentifier) else { fputs("Launcher stayed visible after hide.\n", stderr); exit(5) }
        }
        pump(0.3)
        let timestamp = ProcessInfo.processInfo.systemUptime
        var result: NSRunningApplication? = mode == "reopen" ? current : nil
        var completed = false
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        NSWorkspace.shared.openApplication(at: URL(fileURLWithPath: "/Applications/Volant.app"), configuration: configuration) { app, error in
            if let error { fputs("Open failed: \(error.localizedDescription)\n", stderr) }
            DispatchQueue.main.async { result = app; completed = true }
        }
        let deadline = Date().addingTimeInterval(10)
        while Date() < deadline {
            if result == nil { result = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first }
            if let app = result, visible(app.processIdentifier) {
                print("\(mode),\(trial),\(String(format: "%.3f", (ProcessInfo.processInfo.systemUptime - timestamp) * 1000))")
                break
            }
            if completed && result == nil { exit(4) }
            pump(0.002)
        }
        require(result.map { visible($0.processIdentifier) } == true, "Launcher visibility timed out")
        pump(0.3)
    }
