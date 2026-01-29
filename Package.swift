// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "growlrrr",
    platforms: [
        .macOS(.v13)
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser.git", from: "1.3.0"),
    ],
    targets: [
        .target(
            name: "GrowlrrrCore",
            dependencies: []
        ),
        .executableTarget(
            name: "growlrrr",
            dependencies: [
                "GrowlrrrCore",
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
            ],
            exclude: ["Resources"]
        ),
        .testTarget(
            name: "GrowlrrrTests",
            dependencies: ["GrowlrrrCore"]
        ),
    ]
)
