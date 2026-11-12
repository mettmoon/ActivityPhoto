// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "GeoshopCore",
    platforms: [
        .macOS("27.0"),
        .iOS("27.0"),
    ],
    products: [
        .library(name: "GeoshopCore", targets: ["GeoshopCore"]),
    ],
    targets: [
        .target(name: "GeoshopCore"),
        .testTarget(name: "GeoshopCoreTests", dependencies: ["GeoshopCore"]),
    ]
)
