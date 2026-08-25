// swift-tools-version: 6.0
import PackageDescription

// A dependency-free, pure-Swift Readability implementation. Extracted from the
// Stacks app so its tests run on macOS via `swift test` with no simulator, and
// so it can eventually ship as a standalone package.
let package = Package(
    name: "SwiftReadability",
    platforms: [.iOS(.v18), .macOS(.v14)],
    products: [
        .library(name: "SwiftReadability", targets: ["SwiftReadability"])
    ],
    targets: [
        .target(
            name: "SwiftReadability",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .testTarget(
            name: "SwiftReadabilityTests",
            dependencies: ["SwiftReadability"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        )
    ]
)
