// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "TreeSpace",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "TreeSpace",
            path: "Sources/TreeSpace",
            resources: [
                .process("Resources")
            ]
        )
    ]
)
