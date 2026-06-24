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
        .target(
            name: "GoIOSKit",
            // The go-ios binary is bundled so the app is self-contained (no separate
            // `go-ios` install needed). It is extracted + made executable at runtime.
            // NOTE: this binary is arm64-only — replace with a universal build for Intel.
            // go-ios is MIT-licensed (Copyright (c) 2019 danielpaulus); its license text is
            // shipped next to the binary (go-ios.LICENSE) as MIT requires when redistributing.
            resources: [
                .copy("Resources/go-ios"),
                .copy("Resources/go-ios.LICENSE"),
            ]
        ),
    ]
)
