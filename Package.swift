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
        .executable(name: "kumo", targets: ["KumoCLI"]),
        .executable(name: "KumoService", targets: ["KumoService"])
    ],
    dependencies: [
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
        .executableTarget(
            name: "KumoCLI",
            dependencies: ["KumoCoreKit"]
        ),
        .executableTarget(
            name: "KumoService",
            dependencies: ["KumoCoreKit"]
        ),
        .testTarget(
            name: "KumoCoreTests",
            dependencies: ["KumoCoreKit"]
        )
    ]
)
