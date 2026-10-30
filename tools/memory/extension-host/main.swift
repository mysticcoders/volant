// Opt-in profiling fixture for the extension helper: the production ExtensionHost and WASI command adapter
// run in-process on the repository's sample modules with fictional input. No XPC, launchd or app is involved.
import Foundation
import JavaScriptCore
import VolantCore

startProfile()
let repository = URL(fileURLWithPath: CommandLine.arguments.count > 2 ? CommandLine.arguments[2] : FileManager.default.currentDirectoryPath)
let host = ExtensionHost()

/// Reads a sample module outside the counters; the helper receives these bytes from XPC.
func module(_ path: String) -> Data { uncounted { try! Data(contentsOf: repository.appendingPathComponent(path)) } }
/// Runs an ABI 1 module through the production host and requires the reply the module promises.
func run(_ bytes: Data, _ input: String, capabilities: [String] = [], _ valid: (String) -> Bool) {
    var reply: (String?, String?) = (nil, "No reply")
    host.run(module: bytes, capabilities: capabilities, input: input, timeout: 2) { reply = ($0, $1) }
    precondition(reply.1 == nil && reply.0.map(valid) == true, "ABI 1 run failed: \(reply.1 ?? "unexpected output")")
}
/// Runs an ABI 2 command through the production WASI adapter and requires its Base64 output.
func command(_ bytes: Data, _ input: String) {
    var reply: (String?, String?) = (nil, "No reply")
    host.runCommand(module: bytes, input: input, timeout: 2) { reply = ($0, $1) }
    precondition(reply.1 == nil && reply.0 == Data(input.utf8).base64EncodedString(), "ABI 2 run failed: \(reply.1 ?? "unexpected output")")
}
/// Waits in phases totalling 1, 5 and 15 seconds after the last run, to see whether memory settles on its own.
func idle() {
    phase("idle_1s") { Thread.sleep(forTimeInterval: 1) }
    phase("idle_5s") { Thread.sleep(forTimeInterval: 4) }
    phase("idle_15s") { Thread.sleep(forTimeInterval: 10) }
}
/// Repeats one unit of work in batches of 25 so growth or a plateau shows per batch.
func batches(_ count: Int, prefix: String = "runs", _ work: (Int) -> Void) {
    for batch in 1...count {
        phase("\(prefix)_\(batch * 25)", units: 25) { for index in 0..<25 { autoreleasepool { work((batch - 1) * 25 + index) } } }
    }
}

phase("baseline") {}
let hello = module("extensions/hello-rust/hello.wasm")
let base64 = module("extensions/raycast-base64/encode.wasm")
let greets: (Int) -> (String) -> Bool = { index in { $0 == "Hello, Fixture \(index)!" } }
let clipboard = module("extensions/clipboard-test/clipboard.wasm")
let list = module("tools/extensions/list-fixture/list-fixture.wasm")
let plan = try! ExtensionNetwork.request(phase: "plan", query: "", now: Date(timeIntervalSince1970: 1_800_000_000))
/// One mixed round: the ABI 1 greeting, the clipboard test with its capability, the list fixture's plan and the ABI 2 command.
func round(_ index: Int) {
    run(hello, "Fixture \(index)", greets(index))
    run(clipboard, "fixture \(index)", capabilities: ["clipboard.write"]) { $0.contains("fixture \(index)") }
    run(list, plan) { (try? ExtensionNetwork.plannedURLs(from: $0, hosts: ["fixture.example.com"]))?.isEmpty == false }
    command(base64, "Fixture \(index)")
}
autoreleasepool {
switch scenario {
case "ext-idle":
    idle()
case "ext-hello":
    phase("first_run", units: 1) { run(hello, "Fixture 0", greets(0)) }
    batches(8) { run(hello, "Fixture \($0)", greets($0)) }
    idle()
case "ext-base64":
    phase("first_run", units: 1) { command(base64, "Fixture 0") }
    batches(8) { command(base64, "Fixture \($0)") }
    idle()
case "ext-mixed":
    phase("first_round", units: 4) { round(0) }
    batches(4, prefix: "rounds") { round($0) }
    idle()
case "ext-bursts":
    for burst in 1...3 {
        batches(1, prefix: "burst\(burst)_rounds") { round($0) }
        phase("burst\(burst)_idle_10s") { Thread.sleep(forTimeInterval: 10) }
    }
case "ext-parts":
    batches(1, prefix: "context") { _ in
        let context = JSContext()!
        precondition(context.evaluateScript("1 + 1")?.toInt32() == 2)
    }
    batches(1, prefix: "array_bytes") { _ in
        let context = JSContext()!
        context.setObject([UInt8](base64), forKeyedSubscript: "moduleBytes" as NSString)
        precondition(context.evaluateScript("Uint8Array.from(moduleBytes).length")?.toInt32() == Int32(base64.count))
    }
    batches(1, prefix: "typed_bytes") { _ in
        let context = JSContext()!
        context.setObject(ExtensionHost.bytes(base64, in: context), forKeyedSubscript: "moduleBytes" as NSString)
        precondition(context.evaluateScript("moduleBytes.length")?.toInt32() == Int32(base64.count))
    }
    batches(1, prefix: "compile") { _ in
        let context = JSContext()!
        context.setObject(ExtensionHost.bytes(base64, in: context), forKeyedSubscript: "moduleBytes" as NSString)
        precondition((context.evaluateScript("WebAssembly.Module.imports(new WebAssembly.Module(moduleBytes)).length")?.toInt32() ?? 0) > 0)
    }
    batches(1, prefix: "full_run") { command(base64, "Fixture \($0)") }
    idle()
default: fatalError("Unknown scenario")
}
}
finishProfile()
