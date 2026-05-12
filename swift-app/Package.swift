// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "Popskill",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "Popskill", targets: ["Popskill"])
    ],
    targets: [
        .executableTarget(
            name: "Popskill",
            path: "Sources/Popskill"
        )
    ]
)
