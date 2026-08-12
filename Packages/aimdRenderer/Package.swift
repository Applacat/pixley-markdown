// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "aimdRenderer",
    platforms: [
        .macOS(.v14),
        .iOS(.v17)
    ],
    products: [
        .library(
            name: "aimdRenderer",
            targets: ["aimdRenderer"]
        )
    ],
    targets: [
        .target(
            name: "aimdRenderer",
            path: "Sources/aimdRenderer"
        ),
        .testTarget(
            name: "aimdRendererTests",
            dependencies: ["aimdRenderer"],
            path: "Tests/aimdRendererTests"
        )
    ]
)
