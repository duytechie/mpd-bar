// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "MPDBar",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .library(name: "MPDCore", targets: ["MPDCore"]),
        .executable(name: "MPDBar", targets: ["MPDBar"])
    ],
    targets: [
        .target(name: "MPDCore"),
        .executableTarget(
            name: "MPDBar",
            dependencies: ["MPDCore"]
        ),
        .testTarget(
            name: "MPDCoreTests",
            dependencies: ["MPDCore"]
        )
    ]
)
