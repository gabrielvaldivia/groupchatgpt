// swift-tools-version: 5.9
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "GroupChatGPT",
    platforms: [
        .iOS(.v16),
        .macOS(.v13),
    ],
    products: [
        // Products define the executables and libraries a package produces, making them visible to other packages.
        .library(
            name: "GroupChatGPT",
            targets: ["GroupChatGPT"])
    ],
    dependencies: [
        .package(url: "https://github.com/MacPaw/OpenAI.git", from: "0.2.6"),
        .package(url: "https://github.com/firebase/firebase-ios-sdk.git", from: "11.12.0"),
    ],
    targets: [
        // Targets are the basic building blocks of a package, defining a module or a test suite.
        // Targets can depend on other targets in this package and products from dependencies.
        .target(
            name: "GroupChatGPT",
            dependencies: [
                .product(name: "OpenAI", package: "OpenAI"),
                .product(name: "FirebaseAuth", package: "firebase-ios-sdk"),
                .product(name: "FirebaseFirestore", package: "firebase-ios-sdk"),
            ]),
        .testTarget(
            name: "GroupChatGPTTests",
            dependencies: ["GroupChatGPT"]
        ),
    ]
)
