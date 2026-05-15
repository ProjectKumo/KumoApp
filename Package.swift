// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "Kumo",
    platforms: [
        .macOS(.v15)
    ],
    products: [
        .library(name: "KumoCoreKit", targets: ["KumoCoreKit"]),
        .library(name: "KumoCLIKit", targets: ["KumoCLIKit"]),
        .executable(name: "KumoApp", targets: ["KumoApp"]),
        .executable(name: "kumo", targets: ["KumoCLI"]),
        .executable(name: "KumoService", targets: ["KumoService"])
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser.git", from: "1.7.1"),
        .package(url: "https://github.com/jpsim/Yams.git", from: "5.1.0")
    ],
    targets: [
        .target(
            name: "KumoCoreKit",
            dependencies: ["Yams"],
            resources: [
                .copy("Resources/KumoAgentSkills"),
                .copy("Resources/SubStore")
            ]
        ),
        .executableTarget(
            name: "KumoApp",
            dependencies: ["KumoCoreKit"]
        ),
        .target(
            name: "KumoCLIKit",
            dependencies: [
                "KumoCoreKit",
                .product(name: "ArgumentParser", package: "swift-argument-parser")
            ]
        ),
        .executableTarget(
            name: "KumoCLI",
            dependencies: ["KumoCLIKit"]
        ),
        .executableTarget(
            name: "KumoService",
            dependencies: ["KumoCoreKit"]
        ),
        .testTarget(
            name: "KumoCoreTests",
            dependencies: ["KumoCoreKit"]
        ),
        .testTarget(
            name: "KumoCLITests",
            dependencies: ["KumoCLIKit", "KumoCoreKit"]
        )
    ]
)
