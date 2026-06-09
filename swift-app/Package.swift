// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "Popskill",
    defaultLocalization: "en",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "Popskill", targets: ["Popskill"])
    ],
    dependencies: [
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.9.0")
    ],
    targets: [
        .executableTarget(
            name: "Popskill",
            dependencies: [
                .product(name: "Sparkle", package: "Sparkle")
            ],
            path: "Sources/Popskill"
        ),
        .testTarget(
            name: "PopskillTests",
            dependencies: ["Popskill"],
            path: "Tests/PopskillTests"
        )
    ]
)
