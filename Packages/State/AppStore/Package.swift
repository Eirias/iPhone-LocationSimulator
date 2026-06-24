// swift-tools-version: 6.3
import PackageDescription

let package = Package(
    name: "AppStore",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "AppStore", targets: ["AppStore"]),
    ],
    dependencies: [
        .package(path: "../../Other/Core"),
        .package(path: "../../Other/Models"),
        .package(path: "../../Interface/SpooferInterface"),
    ],
    targets: [
        .target(
            name: "AppStore",
            dependencies: [
                .product(name: "Redux", package: "Core"),
                .product(name: "Logging", package: "Core"),
                "Models",
                "SpooferInterface",
            ]
        ),
    ]
)
