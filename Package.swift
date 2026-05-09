// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "Kumo",
    platforms: [
        .macOS(.v15)
    ],
    products: [
        .library(name: "KumoCoreKit", targets: ["KumoCoreKit"]),
        .executable(name: "KumoApp", targets: ["KumoApp"]),
        .executable(name: "kumo", targets: ["KumoCLI"])
    ],
    targets: [
        .target(name: "KumoCoreKit"),
        .executableTarget(
            name: "KumoApp",
            dependencies: ["KumoCoreKit"]
        ),
        .executableTarget(
            name: "KumoCLI",
            dependencies: ["KumoCoreKit"]
        ),
        .testTarget(
            name: "KumoCoreTests",
            dependencies: ["KumoCoreKit"]
        )
    ]
)
