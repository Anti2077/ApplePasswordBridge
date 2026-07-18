// swift-tools-version: 5.10

import PackageDescription

let package = Package(
    name: "ApplePasswordBridge",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "ApplePasswordBridge", targets: ["ApplePasswordBridge"])
    ],
    targets: [
        .executableTarget(
            name: "ApplePasswordBridge",
            path: "Sources/ApplePasswordBridge"
        ),
        .testTarget(
            name: "ApplePasswordBridgeTests",
            dependencies: ["ApplePasswordBridge"],
            path: "Tests/ApplePasswordBridgeTests"
        )
    ]
)
