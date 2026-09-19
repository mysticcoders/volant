import Foundation
let module = try Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[1]))
var rejected = false
ExtensionHost().run(module: module, capabilities: [], input: "Hello, Volant!", timeout: 2) { output, error in
    guard output == nil, let error else { fatalError("Unexpected ABI 1 acceptance of a WASI module") }
    rejected = true
    print("PASS: production ABI 1 host rejects Javy module: \(error)")
}
precondition(rejected)
var executed = false
ExtensionHost().runCommand(module: module, input: "Hello, Volant!", timeout: 2) { output, error in
    precondition(error == nil && output == "SGVsbG8sIFZvbGFudCE=", "Command adapter failed: \(error ?? "wrong output")")
    executed = true
}
precondition(executed)
print("PASS: production ABI 2 adapter executes the actual Raycast command")
