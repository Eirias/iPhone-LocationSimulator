// swift-tools-version: 6.3
import PackageDescription

let package = Package(
    name: "SpooferInterface",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "SpooferInterface", targets: ["SpooferInterface"]),
    ],
    dependencies: [
        .package(path: "../../Other/Models"),
    ],
    targets: [
        .target(
            name: "SpooferInterface",
            dependencies: ["Models"]
        ),
    ]
)
