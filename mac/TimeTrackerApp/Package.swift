// swift-tools-version: 6.0
import PackageDescription

// The macOS app. Everything platform-specific lives here — NSWorkspace, the
// Accessibility API, AppleScript, GRDB, AppKit/SwiftUI — so TimeTrackerCore can
// stay pure and command-line testable.
let package = Package(
    name: "TimeTrackerApp",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "TimeTrackerApp", targets: ["TimeTrackerApp"]),
    ],
    dependencies: [
        .package(path: "../TimeTrackerCore"),
        .package(url: "https://github.com/groue/GRDB.swift.git", from: "7.0.0"),
    ],
    targets: [
        .executableTarget(
            name: "TimeTrackerApp",
            dependencies: [
                .product(name: "TimeTrackerCore", package: "TimeTrackerCore"),
                .product(name: "GRDB", package: "GRDB.swift"),
            ]
        ),
        .testTarget(
            name: "TimeTrackerAppTests",
            dependencies: ["TimeTrackerApp"]
        ),
    ]
)
