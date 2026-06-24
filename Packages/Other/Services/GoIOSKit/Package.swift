// swift-tools-version: 6.3
import PackageDescription

/// GoIOSKit — thin, dependency-free Swift wrapper around the `go-ios` CLI
/// (github.com/danielpaulus/go-ios). It powers the iOS 17+/26 real-device location
/// spoofing backend: device discovery, DDI auto-mount, set/reset/GPX location.
let package = Package(
    name: "GoIOSKit",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "GoIOSKit", targets: ["GoIOSKit"]),
    ],
    targets: [
        .target(name: "GoIOSKit"),
    ]
)
