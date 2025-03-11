// swift-tools-version: 6.0
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "MetalBlurHash",
    platforms: [
        .iOS(.v15),
        .macCatalyst(.v15),
        .visionOS(.v1)
    ],
    products: [
        .library(
            name: "MetalBlurHash",
            targets: ["MetalBlurHash"]),
    ],
    targets: [
        .target(
            name: "MetalBlurHash"
        ),
        .testTarget(
            name: "MetalBlurHashTests",
            dependencies: ["MetalBlurHash"],
            resources: [.process("Images")]
        ),
    ]
)
