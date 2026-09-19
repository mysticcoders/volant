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
print("PASS: actual WASM greeting, UTF-8, input/output limits, malformed modules and denied imports")
