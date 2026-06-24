// swift-tools-version: 6.3
import PackageDescription

let package = Package(
    name: "MapFeature",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "MapFeature", targets: ["MapFeature"]),
    ],
    dependencies: [
        .package(path: "../../State/AppStore"),
        .package(path: "../../Other/DesignSystem"),
        .package(path: "../../Other/Localization"),
        .package(path: "../../Other/Models"),
    ],
    targets: [
        .target(
            name: "MapFeature",
            dependencies: ["AppStore", "DesignSystem", "Localization", "Models"]
        ),
    ]
)
