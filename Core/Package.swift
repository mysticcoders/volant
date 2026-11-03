// swift-tools-version: 5.9
import PackageDescription

// VolantCore holds the portable, dependency-free half of Volant: search ranking,
// calculation, unit and emoji lookup, Markdown block parsing, preferences, and the
// agent, Herdr and extension protocol types. It imports Foundation and nothing else,
// so platform code cannot leak back in and the core can be tested without the app.
let package = Package(
    name: "VolantCore",
    platforms: [.macOS("15.0")],
    products: [
        .library(name: "VolantCore", type: .static, targets: ["VolantCore"])
    ],
    targets: [
        // Swift marks public declarations as always used, so each helper would keep all of the core.
        // Internalizing at link lets DEAD_CODE_STRIPPING drop what a binary does not reach.
        .target(name: "VolantCore", swiftSettings: [.unsafeFlags(["-Xfrontend", "-internalize-at-link"])]),
        .testTarget(name: "VolantCoreTests", dependencies: ["VolantCore"])
    ]
)
