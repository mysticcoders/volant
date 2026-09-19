import Foundation
let module = try Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[1]))
var rejected = false
ExtensionHost().run(module: module, capabilities: [], input: "Hello, Volant!", timeout: 2) { output, error in
    guard output == nil, let error else { fatalError("Unexpected ABI 1 acceptance of a WASI module") }
    rejected = true
    print("PASS: production ABI 1 host rejects Javy module: \(error)")
}
precondition(rejected)
