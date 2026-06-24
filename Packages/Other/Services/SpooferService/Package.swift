// swift-tools-version: 6.3
import PackageDescription

let package = Package(
    name: "SpooferService",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "SpooferService", targets: ["SpooferService"]),
    ],
    dependencies: [
        .package(path: "../GoIOSKit"),
        .package(path: "../../Models"),
        .package(path: "../../Core"),
        .package(path: "../../../Interface/SpooferInterface"),
    ],
    targets: [
        .target(
            name: "SpooferService",
            dependencies: [
                "GoIOSKit",
                "Models",
                "SpooferInterface",
                .product(name: "Logging", package: "Core"),
            ]
        ),
    ]
)
