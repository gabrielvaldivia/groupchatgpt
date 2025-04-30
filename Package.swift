// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "GroupChatGPT",
    platforms: [
        .iOS(.v16)
    ],
    dependencies: [
        .package(url: "https://github.com/firebase/firebase-ios-sdk.git", from: "10.0.0"),
        .package(url: "https://github.com/MacPaw/OpenAI.git", from: "0.4.2"),
    ],
    targets: [
        .executableTarget(
            name: "GroupChatGPT",
            dependencies: [
                .product(name: "FirebaseAuth", package: "firebase-ios-sdk"),
                .product(name: "FirebaseFirestore", package: "firebase-ios-sdk"),
                .product(name: "FirebaseFirestoreSwift", package: "firebase-ios-sdk"),
                .product(name: "FirebaseCore", package: "firebase-ios-sdk"),
                .product(name: "OpenAI", package: "OpenAI"),
            ],
            path: "GroupChatGPT"
        )
    ]
)
