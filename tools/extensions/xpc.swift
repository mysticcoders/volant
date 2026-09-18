import Foundation

let root = URL(fileURLWithPath: CommandLine.arguments[1])
let config = root.appendingPathComponent("config.json")
try Data("{}".utf8).write(to: config)
let manager = ExtensionManager(configURL: config, roots: [root.appendingPathComponent("hello"), root.appendingPathComponent("spin")])
manager.reload()
guard let hello = manager.search("hello").first, let spin = manager.search("spin").first else { fatalError("Missing isolated fixtures: \(manager.loadErrors)") }
try manager.setEnabled(hello, true)
try manager.setEnabled(spin, true)
var done = false, failure: String?
manager.run(hello, input: "Andrew") { result in
    guard case .success("Hello, Andrew!") = result else { failure = "First XPC greeting failed: \(result)"; done = true; return }
    manager.run(spin, input: "") { result in
        guard case .failure = result else { failure = "Runaway returned success"; done = true; return }
        manager.run(hello, input: "world") { result in
            if case .success("Hello, world!") = result {} else { failure = "XPC did not recover: \(result)" }
            done = true
        }
    }
}
let deadline = Date().addingTimeInterval(30)
while !done && Date() < deadline { RunLoop.main.run(until: Date().addingTimeInterval(0.02)) }
if !done || failure != nil { fputs("FAIL: \(failure ?? "XPC timeout")\n", stderr); exit(1) }
print("PASS: signed sandboxed XPC executes Hello World, reports runaway termination, and executes a fresh greeting afterward")
