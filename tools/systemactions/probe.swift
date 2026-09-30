import AppKit
import CoreGraphics
import Foundation

/// One system action per invocation, reporting a single JSON line. Actions that change session
/// state (lock, sleep, restart dialog) are run only inside a disposable Tart guest. Automation
/// permission is checked without asking, so no probe can raise a consent dialog.
setbuf(stdout, nil)
let sandboxed = ProcessInfo.processInfo.environment["APP_SANDBOX_CONTAINER_ID"] != nil
var report: [String: Any] = ["sandboxed": sandboxed, "os": ProcessInfo.processInfo.operatingSystemVersionString]
func finish(_ values: [String: Any]) -> Never {
    report.merge(values) { $1 }
    let data = try! JSONSerialization.data(withJSONObject: report, options: [.sortedKeys])
    print(String(decoding: data, as: UTF8.self))
    exit(0)
}
func locked() -> Bool? {
    guard let session = CGSessionCopyCurrentDictionary() as? [String: Any] else { return nil }
    return session["CGSSessionScreenIsLocked"] as? Bool ?? false
}
/// Owner names are readable without Screen Recording; window titles are not, and are not needed.
func windowOwners() -> [String] {
    let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] ?? []
    return windows.compactMap { $0[kCGWindowOwnerName as String] as? String }
}
func run(_ path: String, _ arguments: [String]) -> [String: Any] {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: path)
    process.arguments = arguments
    let errors = Pipe()
    process.standardOutput = FileHandle.nullDevice
    process.standardError = errors
    do { try process.run() } catch { return ["launched": false, "error": String(describing: error)] }
    process.waitUntilExit()
    let message = String(decoding: errors.fileHandleForReading.readDataToEndOfFile().prefix(300), as: UTF8.self)
    return ["launched": true, "status": Int(process.terminationStatus), "stderr": message]
}
/// Asks whether sending would be allowed, never prompting. -1743 is denied, -1744 would prompt,
/// -600 is the target not running, 0 is allowed.
func automation(_ bundle: String, _ eventClass: AEEventClass, _ eventID: AEEventID) -> Int {
    let target = NSAppleEventDescriptor(bundleIdentifier: bundle)
    return Int(AEDeterminePermissionToAutomateTarget(target.aeDesc, eventClass, eventID, false))
}
func code(_ text: String) -> UInt32 { text.utf8.reduce(0) { $0 << 8 | UInt32($1) } }

switch CommandLine.arguments.dropFirst().first ?? "" {
case "permissions":
    finish([
        "loginwindow.showRestartDialog": automation("com.apple.loginwindow", code("aevt"), code("rrst")),
        "loginwindow.showLogoutDialog": automation("com.apple.loginwindow", code("aevt"), code("logo")),
        "finder.emptyTrash": automation("com.apple.finder", code("fndr"), code("empt")),
        "systemevents.any": automation("com.apple.systemevents", code("****"), code("****")),
        "lockedBefore": locked() as Any
    ])
case "lock":
    let before = locked()
    guard let handle = dlopen("/System/Library/PrivateFrameworks/login.framework/Versions/Current/login", RTLD_NOW) else {
        finish(["loaded": false, "dlerror": String(cString: dlerror())])
    }
    guard let symbol = dlsym(handle, "SACLockScreenImmediate") else { finish(["loaded": true, "symbol": false]) }
    typealias Lock = @convention(c) () -> Int32
    let result = unsafeBitCast(symbol, to: Lock.self)()
    Thread.sleep(forTimeInterval: 3)
    finish(["loaded": true, "symbol": true, "result": Int(result), "lockedBefore": before as Any, "lockedAfter": locked() as Any])
case "screensaver":
    let url = URL(fileURLWithPath: "/System/Library/CoreServices/ScreenSaverEngine.app")
    let done = DispatchSemaphore(value: 0)
    var failure: String?
    NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration()) { _, error in
        failure = error.map { String(describing: $0) }; done.signal()
    }
    _ = done.wait(timeout: .now() + 10)
    Thread.sleep(forTimeInterval: 2)
    let running = NSWorkspace.shared.runningApplications.contains { $0.bundleIdentifier == "com.apple.ScreenSaver.Engine" }
    finish(["openError": failure as Any, "engineRunning": running])
case "displaysleep":
    finish(["pmset": run("/usr/bin/pmset", ["displaysleepnow"])])
case "sleep":
    finish(["pmset": run("/usr/bin/pmset", ["sleepnow"])])
case "restartdialog":
    let before = windowOwners()
    let target = NSAppleEventDescriptor(bundleIdentifier: "com.apple.loginwindow")
    let event = NSAppleEventDescriptor(eventClass: code("aevt"), eventID: code("rrst"), targetDescriptor: target,
                                       returnID: AEReturnID(kAutoGenerateReturnID), transactionID: AETransactionID(kAnyTransactionID))
    var sendError: String?
    do { _ = try event.sendEvent(options: [.noReply], timeout: 5) } catch { sendError = String(describing: error) }
    Thread.sleep(forTimeInterval: 3)
    var appeared = windowOwners()
    for owner in before { if let index = appeared.firstIndex(of: owner) { appeared.remove(at: index) } }
    finish(["sendError": sendError as Any, "windowsAppeared": appeared])
default:
    finish(["error": "unknown action"])
}
