// swift-tools-version: 6.0
import PackageDescription

// Pure domain logic for the Time Tracker macOS app.
//
// Deliberately dependency-free and AppKit-free: everything here is testable
// with `swift test` from the command line, and could back an iOS companion
// later. All platform I/O (AX observers, NSWorkspace, GRDB) lives in the app
// target and talks to this package through protocols.
let package = Package(
    name: "TimeTrackerCore",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "TimeTrackerCore", targets: ["TimeTrackerCore"]),
    ],
    targets: [
        .target(name: "TimeTrackerCore"),
        .testTarget(
            name: "TimeTrackerCoreTests",
            dependencies: ["TimeTrackerCore"],
            resources: [.copy("Fixtures")]
        ),
    ]
)
