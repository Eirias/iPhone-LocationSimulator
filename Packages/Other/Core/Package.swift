// swift-tools-version: 6.3
import PackageDescription

let package = Package(
    name: "Core",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "Redux", targets: ["Redux"]),
        .library(name: "Logging", targets: ["Logging"]),
    ],
    targets: [
        .target(name: "Redux"),
        .target(name: "Logging"),
    ]
)
