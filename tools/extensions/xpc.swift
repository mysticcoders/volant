import Foundation

let root = URL(fileURLWithPath: CommandLine.arguments[1])
let config = root.appendingPathComponent("config.json")
try Data("{}".utf8).write(to: config)
let manager = ExtensionManager(configURL: config, roots: [root.appendingPathComponent("hello"), root.appendingPathComponent("spin")])
manager.reload()
try manager.setCommunityAllowed(true, expected: false)
guard let hello = manager.search("hello").first, let spin = manager.search("spin").first else { fatalError("Missing isolated fixtures: \(manager.loadErrors)") }
try manager.setEnabled(hello, true)
try manager.setEnabled(spin, true)
var done = false, failure: String?
func checkRevocation() {
    manager.run(spin, input: "") { result in
        guard case .failure(ExtensionManager.ExtensionError.communityDisabled) = result else {
            failure = "Master switch did not revoke the pending/active run: \(result)"; done = true; return
        }
        guard ExtensionApproval.enabled(spin.manifest, at: config) else {
            failure = "Master switch erased the individual approval"; done = true; return
        }
        manager.run(hello, input: "fictional") { blocked in
            if case .failure(ExtensionManager.ExtensionError.communityDisabled) = blocked {} else {
                failure = "Stale approved command bypassed master switch"
            }
            done = true
        }
    }
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
        do { try manager.setCommunityAllowed(false, expected: true) }
        catch { failure = "Master switch write failed"; done = true }
    }
}
manager.run(hello, input: "Andrew") { result in
    guard case .success("Hello, Andrew!") = result else { failure = "First XPC greeting failed: \(result)"; done = true; return }
    manager.run(spin, input: "") { result in
        guard case .failure = result else { failure = "Runaway returned success"; done = true; return }
        manager.run(hello, input: "world") { result in
            if case .success("Hello, world!") = result { checkRevocation() }
            else { failure = "XPC did not recover: \(result)"; done = true }
        }
    }
}
let deadline = Date().addingTimeInterval(30)
while !done && Date() < deadline { RunLoop.main.run(until: Date().addingTimeInterval(0.02)) }
if !done || failure != nil { fputs("FAIL: \(failure ?? "XPC timeout")\n", stderr); exit(1) }
print("PASS: signed sandboxed XPC executes Hello World, recovers after runaway termination, and revokes community execution without erasing individual approval")
