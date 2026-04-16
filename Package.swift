// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "StateSwitchMenubar",
    platforms: [
        .macOS(.v13),
    ],
    products: [
        .executable(
            name: "StateSwitchMenubar",
            targets: ["StateSwitchMenubar"]
        ),
    ],
    targets: [
        .executableTarget(
            name: "StateSwitchMenubar",
            path: "Sources/StateSwitchMenubar"
        ),
        .testTarget(
            name: "StateSwitchMenubarTests",
            dependencies: ["StateSwitchMenubar"],
            path: "Tests/StateSwitchMenubarTests"
        ),
    ]
)
