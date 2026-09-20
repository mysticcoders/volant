import AppKit
import Darwin

// Sandboxed caller. Mirrors what the launcher would do: choose a target, then ask the helper.
// It carries Volant's own App Sandbox entitlement so the comparison is honest.

func report(_ probe: String, _ outcome: String) {
    print("\(probe.padding(toLength: 46, withPad: " ", startingAt: 0)) \(outcome)")
}

let sandboxed = FileManager.default.homeDirectoryForCurrentUser.path.contains("/Library/Containers/")
let target = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "com.apple.TextEdit"
print("=== privileged helper spike ===")
report("client sandboxed", "\(sandboxed)")

guard let app = NSWorkspace.shared.runningApplications.first(where: { $0.bundleIdentifier == target }) else {
    report("target", "\(target) NOT RUNNING")
    exit(2)
}
let pid = app.processIdentifier
report("target", "\(target) pid \(pid)")

// Baseline: prove again, in this exact process, that the sandboxed side cannot do it itself.
report("client kill(pid, 0)", kill(pid, 0) == 0 ? "permitted" : "EPERM")
report("client terminate()", app.terminate() ? "returned true" : "returned false")
Thread.sleep(forTimeInterval: 2)
report("target after client terminate()", NSRunningApplication(processIdentifier: pid) == nil ? "GONE" : "still running")

guard NSRunningApplication(processIdentifier: pid) != nil else {
    report("RESULT", "client quit it unaided; helper not exercised")
    exit(0)
}

let connection = NSXPCConnection(serviceName: "com.mysticcoders.volant.privaccess")
connection.remoteObjectInterface = NSXPCInterface(with: VolantPrivAccessHostProtocol.self)
connection.invalidationHandler = { print("connection invalidated") }
connection.interruptionHandler = { print("connection interrupted") }
connection.resume()

let proxy = connection.remoteObjectProxyWithErrorHandler { error in
    report("XPC error", "\(error.localizedDescription)")
    exit(3)
} as? VolantPrivAccessHostProtocol

guard let proxy else { report("RESULT", "no proxy"); exit(3) }

let probed = DispatchSemaphore(value: 0)
proxy.probe(pid: pid) { outcome in
    report("helper kill(pid, 0)", outcome)
    probed.signal()
}
_ = probed.wait(timeout: .now() + 15)

// Revalidation check: the helper must refuse a pid/bundle pair that no longer agrees.
let mismatched = DispatchSemaphore(value: 0)
proxy.terminate(pid: pid, bundleIdentifier: "com.example.not.this.app") { reason in
    report("helper refuses mismatched bundle", reason ?? "ACCEPTED — revalidation is broken")
    mismatched.signal()
}
_ = mismatched.wait(timeout: .now() + 15)

let done = DispatchSemaphore(value: 0)
proxy.terminate(pid: pid, bundleIdentifier: target) { reason in
    report("helper terminate", reason ?? "reported success")
    done.signal()
}
_ = done.wait(timeout: .now() + 20)

Thread.sleep(forTimeInterval: 2)
let gone = NSRunningApplication(processIdentifier: pid) == nil
report("RESULT", gone ? "HELPER QUIT THE APP" : "target still running")
connection.invalidate()
exit(gone ? 0 : 1)
