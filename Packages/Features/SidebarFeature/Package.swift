// swift-tools-version: 6.3
import PackageDescription

let package = Package(
    name: "SidebarFeature",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "SidebarFeature", targets: ["SidebarFeature"]),
    ],
    dependencies: [
        .package(path: "../../State/AppStore"),
        .package(path: "../../Other/DesignSystem"),
        .package(path: "../../Other/Localization"),
        .package(path: "../../Other/Models"),
    ],
    targets: [
        .target(
            name: "SidebarFeature",
            dependencies: ["AppStore", "DesignSystem", "Localization", "Models"]
        ),
    ]
)
