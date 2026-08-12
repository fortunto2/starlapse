// swift-tools-version: 6.0
import PackageDescription

// SkyKit is the domain layer: where things are in the sky, and what is worth shooting
// tonight. It has zero platform dependencies — no AVFoundation, no UIKit, no CoreLocation —
// which is what lets `starlapse-sky` run the exact same math on a Mac in milliseconds
// instead of round-tripping through a simulator. Clean Architecture: entities point inward.
let package = Package(
    name: "SkyKit",
    platforms: [
        .iOS(.v18),
        .macOS(.v15),
    ],
    products: [
        .library(name: "SkyKit", targets: ["SkyKit"]),
        .library(name: "StackKit", targets: ["StackKit"]),
        .executable(name: "starlapse-sky", targets: ["SkyKitCLI"]),
    ],
    targets: [
        .target(name: "SkyKit"),
        // Star detection and frame registration: pure arithmetic over Float buffers, with
        // no Metal or AVFoundation in sight. That keeps it testable against synthetic star
        // fields rotated by a known angle — the only way to know alignment works without
        // standing in a field at 2am.
        .target(name: "StackKit"),
        .executableTarget(name: "SkyKitCLI", dependencies: ["SkyKit"]),
        .testTarget(name: "SkyKitTests", dependencies: ["SkyKit"]),
        .testTarget(name: "StackKitTests", dependencies: ["StackKit"]),
    ]
)
