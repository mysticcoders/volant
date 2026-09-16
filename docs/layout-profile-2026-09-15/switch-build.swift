import AppKit
let app = NSApplication.shared
app.setActivationPolicy(.prohibited)
func pump() { RunLoop.main.run(until: Date().addingTimeInterval(0.01)) }
for current in NSRunningApplication.runningApplications(withBundleIdentifier: "com.mysticcoders.volant") {
    guard current.terminate() else { exit(2) }
    let deadline = Date().addingTimeInterval(10)
    while kill(current.processIdentifier, 0) == 0 && Date() < deadline { pump() }
    guard kill(current.processIdentifier, 0) != 0 else { exit(3) }
}
RunLoop.main.run(until: Date().addingTimeInterval(0.5))
let path = CommandLine.arguments[1]
if path == "--quit" { exit(0) }
var done = false
var success = false
NSWorkspace.shared.openApplication(at: URL(fileURLWithPath: path), configuration: NSWorkspace.OpenConfiguration()) { running, error in
    if let error { fputs("Launch error code: \((error as NSError).code)\n", stderr) }
    success = running?.bundleURL?.resolvingSymlinksInPath().path == URL(fileURLWithPath: path).resolvingSymlinksInPath().path
    done = true
}
let deadline = Date().addingTimeInterval(10)
while !done && Date() < deadline { pump() }
guard success else { exit(4) }
RunLoop.main.run(until: Date().addingTimeInterval(2))
