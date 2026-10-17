// swift-tools-version: 6.0
// Copied to the root of the source copy by Tools/release/build_app.sh. Builds the LaneKeep app target
// with the Command Line Tools the way LaneKeep.xcodeproj does: Swift 6, macOS 14, LaneKeepKit, and
// KeyboardShortcuts (here the patched copy in Vendor/).
import PackageDescription

let package = Package(
    name: "LaneKeepRelease",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(path: "Packages/LaneKeepKit"),
        .package(path: "Vendor/KeyboardShortcuts"),
    ],
    targets: [
        .executableTarget(
            name: "LaneKeep",
            dependencies: [
                .product(name: "LaneKeepCore", package: "LaneKeepKit"),
                .product(name: "LaneKeepSystem", package: "LaneKeepKit"),
                .product(name: "KeyboardShortcuts", package: "KeyboardShortcuts"),
            ],
            path: "LaneKeep",
            exclude: ["Assets.xcassets"]
        ),
    ]
)
