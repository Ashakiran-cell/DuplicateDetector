// swift-tools-version: 5.9
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "DuplicateDetector",
    platforms: [
        .macOS(.v10_15),
        .iOS(.v13)
    ],
    products: [
        // Products can be used to vend plugins, making them visible to other packages.
        .plugin(
            name: "DuplicateDetector",
            targets: ["DuplicateDetector"]),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-syntax.git", from: "510.0.0"),
    ],
    targets: [
        // Targets are the basic building blocks of a package, defining a module or a test suite.
        // Targets can depend on other targets in this package and products from dependencies.
        .plugin(
            name: "DuplicateDetector",
            capability: .buildTool(),
            dependencies: [
                .target(name: "DuplicateDetectorTool")
            ]
        ),
        .executableTarget(
            name: "DuplicateDetectorTool",
            dependencies: [
                .product(name: "SwiftSyntax", package: "swift-syntax"),
                .product(name: "SwiftParser", package: "swift-syntax"),
            ],
            path: "Sources/DuplicateDetectorTool"
        )
    ]
)
