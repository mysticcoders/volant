// swift-tools-version: 5.9
import PackageDescription

// Native macOS build of the comparison program: the real VolantCore, for checking the WASI answers.
let package = Package(
    name: "NativeCompare",
    platforms: [.macOS("15.0")],
    dependencies: [.package(path: "../../../Core")],
    targets: [.executableTarget(name: "NativeCompare", dependencies: [.product(name: "VolantCore", package: "Core")])]
)
