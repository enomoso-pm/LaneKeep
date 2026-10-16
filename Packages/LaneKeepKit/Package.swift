// swift-tools-version: 6.0
import PackageDescription

// LaneKeepKit holds everything that is not SwiftUI:
//
// - LaneKeepCore   : platform-independent logic (data model, geometry, window matching,
//                    the restore engine, summaries, persistence). Builds and tests on Linux too.
// - LaneKeepSystem : the macOS side (Accessibility API, NSScreen, NSWorkspace).
// - lanekeep       : a small command-line tool (spec §11 step 1) built on the two libraries.
let package = Package(
    name: "LaneKeepKit",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(name: "LaneKeepCore", targets: ["LaneKeepCore"]),
        .library(name: "LaneKeepSystem", targets: ["LaneKeepSystem"]),
        .executable(name: "lanekeep", targets: ["LaneKeepCLI"])
    ],
    targets: [
        .target(name: "LaneKeepCore"),
        .target(
            name: "LaneKeepSystem",
            dependencies: ["LaneKeepCore"]
        ),
        .executableTarget(
            name: "LaneKeepCLI",
            dependencies: ["LaneKeepCore", "LaneKeepSystem"]
        ),
        .testTarget(
            name: "LaneKeepCoreTests",
            dependencies: ["LaneKeepCore"]
        )
    ],
    swiftLanguageModes: [.v6]
)
