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
        // 2.9.4 起：2.9.2 含两项 high-complex 安全修复（delta 更新 symlink 防护 /
        // 安装器连接验证）——下限钉死，防止 resolved 回退到带洞版本
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.9.4")
    ],
    targets: [
        .executableTarget(
            name: "Popskill",
            dependencies: [
                .product(name: "Sparkle", package: "Sparkle")
            ],
            path: "Sources/Popskill",
            resources: [
                .process("Resources")
            ]
        ),
        .testTarget(
            name: "PopskillTests",
            dependencies: ["Popskill"],
            path: "Tests/PopskillTests"
        )
    ]
)
