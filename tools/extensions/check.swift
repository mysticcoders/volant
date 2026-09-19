import Foundation
let root = URL(fileURLWithPath: CommandLine.arguments[1])
let module = try Data(contentsOf: root.appendingPathComponent("extensions/hello-rust/hello.wasm"))
let engine = ExtensionHost()
func evaluate(_ data: Data, input: String = "", capabilities: [String] = [], timeout: Double = 2) -> (String?, String?) {
    var result: (String?, String?) = (nil, "No reply")
    engine.run(module: data, capabilities: capabilities, input: input, timeout: timeout) { result = ($0, $1) }
    return result
}
if CommandLine.arguments.contains("--spin") {
    let spin = try Data(contentsOf: root.appendingPathComponent("extensions/spin-rust/spin.wasm"))
    _ = evaluate(spin, timeout: 0.5)
    fatalError("Watchdog failed to terminate looping WASM")
}
if CommandLine.arguments.contains("--command-spin") {
    let spin = try Data(contentsOf: root.appendingPathComponent("tools/extensions/wasi-fixtures/spin.wasm"))
    engine.runCommand(module: spin, input: "", timeout: 0.5) { _, _ in fatalError("Command watchdog failed") }
    fatalError("Command watchdog failed to terminate")
}
func check(_ condition: Bool, _ message: String) { if !condition { fputs("FAIL: \(message)\n", stderr); exit(1) } }
let hello = evaluate(module, input: "Andrew")
check(hello.0 == "Hello, Andrew!" && hello.1 == nil, "WASM returns real greeting: \(String(describing: hello))")
check(evaluate(module).0 == "Hello, world!", "Empty input")
check(evaluate(module, input: "世界 👋").0 == "Hello, 世界 👋!", "UTF-8 round trip")
check(evaluate(module, input: String(repeating: "x", count: 65_537)).1 != nil, "Input limit")
check(evaluate(module, input: String(repeating: "x", count: 65_530)).1 != nil, "Output limit")
check(evaluate(module, timeout: .infinity).1 != nil, "Finite watchdog")
check(evaluate(Data([0])).1 != nil, "Malformed module")
// Valid bounded module importing vey.log; denied before any missing-export checks.
let imported = Data([0,97,115,109,1,0,0,0, 1,6,1,96,2,127,127,0, 2,11,1,3,118,101,121,3,108,111,103,0,0, 5,4,1,1,1,1])
check(evaluate(imported).1?.contains("not granted") == true, "Undeclared capability denied")
let base64 = try Data(contentsOf: root.appendingPathComponent("extensions/raycast-base64/encode.wasm"))
let legacyRejection = evaluate(base64)
check(legacyRejection.0 == nil && legacyRejection.1?.contains("not granted") == true, "ABI 1 never silently accepts WASI imports: \(legacyRejection.1 ?? "no error")")
for input in ["", "Hello, Volant!", "café ☕ 日本語", String(repeating: "a", count: 4096)] {
    var output: String?, failure: String?
    engine.runCommand(module: base64, input: input, timeout: 2) { output = $0; failure = $1 }
    check(output == Data(input.utf8).base64EncodedString() && failure == nil, "Production WASI adapter executes real TypeScript: \(failure ?? "wrong output")")
}
var overLimit = false
var exactLimit = false
engine.runCommand(module: base64, input: String(repeating: "a", count: 49152), timeout: 2) { exactLimit = $0?.utf8.count == 65536 && $1 == nil }
check(exactLimit, "Exactly 64 KiB of Base64 output succeeds")
engine.runCommand(module: base64, input: String(repeating: "a", count: 49153), timeout: 2) { overLimit = $0 == nil && $1 != nil }
check(overLimit, "Command input/output boundary does not return truncated success")
func commandProbe(_ name: String, input: String = "OK") throws -> (String?, String?) {
    let bytes = try Data(contentsOf: root.appendingPathComponent("tools/extensions/wasi-fixtures/\(name).wasm"))
    var result: (String?, String?) = (nil, "No reply")
    engine.runCommand(module: bytes, input: input, timeout: 2) { result = ($0, $1) }
    return result
}
check(try commandProbe("streams").0 == "OK", "Bounded streams, partial reads, EOF, fd rights, closed fds, empty environment and frozen clock")
check(try commandProbe("zeroExit").0 == "OK", "proc_exit(0) terminates only this command")
check(try commandProbe("caughtExit").0 == "OK", "Caught exit cannot resume command I/O")
for name in ["failedExit", "bounds", "vectorLimit", "outputLimit", "stderrLimit", "invalidUTF8", "callLimit", "filesystem", "network", "prototype"] {
    let result = try commandProbe(name)
    check(result.0 == nil && result.1 != nil, "Command rejects \(name) without partial output")
}
check(try commandProbe("streams").0 == "OK", "Fresh command recovers after rejected calls")
print("PASS: production ABI 2 executes Raycast TypeScript and enforces stream, import, pointer, output and host-call boundaries")
print("PASS: actual WASM greeting, UTF-8, input/output limits, malformed modules and denied imports")
