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
        .library(
            name: "SBSNBackend",
            targets: ["SBSNBackend"]
        ),
        .library(
            name: "SBSNUI",
            targets: ["SBSNUI"]
        ),
    ],
    dependencies: [
        .package(url: "https://github.com/firebase/firebase-ios-sdk", from: "13.0.0"),
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
        // Firebase는 이 모듈 안에서만 다룬다. 앱과 SBSNCore는 Firebase 타입을 직접 쓰지 않는다.
        .target(
            name: "SBSNBackend",
            dependencies: [
                "SBSNCore",
                .product(name: "FirebaseCore", package: "firebase-ios-sdk"),
                .product(name: "FirebaseAuth", package: "firebase-ios-sdk"),
                .product(name: "FirebaseFirestore", package: "firebase-ios-sdk"),
                .product(name: "FirebaseMessaging", package: "firebase-ios-sdk"),
                .product(name: "FirebaseStorage", package: "firebase-ios-sdk"),
            ],
            swiftSettings: [
                .enableUpcomingFeature("ApproachableConcurrency"),
            ],
        ),
        // 작가 앱과 고객 앱이 같이 쓰는 화면(매칭 지도, 채팅).
        .target(
            name: "SBSNUI",
            dependencies: ["SBSNCore", "SBSNBackend"],
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
