// swift-tools-version: 5.9
import PackageDescription

// A WASI command that answers one launcher query with VolantCore's own calculator, for the
// website's "Try Volant" spike. It reads a JSON request on stdin and writes JSON answers to stdout.
// VolantCalc links VolantCore's Calculator, Units and Currency sources unchanged (symlinks) plus a
// localization shim, because Foundation for WASI has no String Catalog API.
let package = Package(
    name: "VolantAnswers",
    targets: [
        .target(name: "VolantCalc"),
        .executableTarget(name: "VolantAnswers", dependencies: ["VolantCalc"])
    ]
)
