// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "MacDevCleanUI",
    platforms: [
        .macOS(.v14),
    ],
    products: [
        .executable(name: "MacDevCleanApp", targets: ["MacDevCleanApp"]),
    ],
    targets: [
        .executableTarget(
            name: "MacDevCleanApp",
            path: "Sources/MacDevCleanApp"
        ),
        .testTarget(
            name: "MacDevCleanAppTests",
            dependencies: ["MacDevCleanApp"],
            path: "Tests/MacDevCleanAppTests"
        ),
    ]
)
