// swift-tools-version: 6.3
import PackageDescription

let package = Package(
    name: "Localization",
    defaultLocalization: "en",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "Localization", targets: ["Localization"]),
    ],
    targets: [
        .target(
            name: "Localization",
            resources: [.process("Resources")]
        ),
    ]
)
