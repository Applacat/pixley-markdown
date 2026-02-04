// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "AIMDReader",
    platforms: [.macOS(.v26)],
    targets: [
        .executableTarget(
            name: "AIMDReader",
            path: ".",
            exclude: [
                "cal",
                "docs",
                "Open",
                "project.yml",
                "CLAUDE.md",
                "Resources/Info.plist",
                "Resources/AIMDReader.entitlements"
            ],
            sources: ["Sources"],
            resources: [
                .process("Resources/Assets.xcassets"),
                .copy("Resources/Welcome"),
                .copy("Resources/PrivacyInfo.xcprivacy")
            ]
        )
    ]
)
