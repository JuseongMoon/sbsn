// swift-tools-version: 6.4
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "SBSNKit",
    platforms: [
        .iOS(.v17),
        // 앱은 iOS 전용이다. macOS는 `swift test`를 맥에서 돌리기 위해서만 둔다.
        .macOS(.v14),
    ],
    products: [
        // Products define the executables and libraries a package produces, making them visible to other packages.
        .library(
            name: "SBSNCore",
            targets: ["SBSNCore"]
        ),
        .library(
            name: "SBSNCameraTransfer",
            targets: ["SBSNCameraTransfer"]
        ),
    ],
    targets: [
        // Targets are the basic building blocks of a package, defining a module or a test suite.
        // Targets can depend on other targets in this package and products from dependencies.
        .target(
            name: "SBSNCore",
            swiftSettings: [
                .enableUpcomingFeature("ApproachableConcurrency"),
            ],
        ),
        .testTarget(
            name: "SBSNCoreTests",
            dependencies: ["SBSNCore"],
            swiftSettings: [
                .enableUpcomingFeature("ApproachableConcurrency"),
            ],
        ),
        .target(
            name: "SBSNCameraTransfer",
            swiftSettings: [
                .enableUpcomingFeature("ApproachableConcurrency"),
            ],
        ),
        .testTarget(
            name: "SBSNCameraTransferTests",
            dependencies: ["SBSNCameraTransfer"],
            swiftSettings: [
                .enableUpcomingFeature("ApproachableConcurrency"),
            ],
        ),
    ]
)
