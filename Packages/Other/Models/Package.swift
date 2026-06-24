// swift-tools-version: 6.3
import PackageDescription

let package = Package(
    name: "Models",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "Models", targets: ["Models"]),
    ],
    targets: [
        .target(name: "Models"),
    ]
)
