// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "MacOSFixer",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "macosfixer", targets: ["MacOSFixer"]),
        .library(name: "MacOSFixerCore", targets: ["MacOSFixerCore"]),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser", from: "1.3.0"),
        .package(url: "https://github.com/apple/swift-system", from: "1.4.0"),
    ],
    targets: [
        .executableTarget(
            name: "MacOSFixer",
            dependencies: [
                "MacOSFixerCore",
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
            ],
            path: "Sources/MacOSFixer"
        ),
        .target(
            name: "MacOSFixerCore",
            dependencies: [
                .product(name: "SystemPackage", package: "swift-system"),
            ],
            path: "Sources/MacOSFixerCore"
        ),
        .testTarget(
            name: "MacOSFixerTests",
            dependencies: ["MacOSFixerCore"],
            path: "Tests"
        ),
    ]
)