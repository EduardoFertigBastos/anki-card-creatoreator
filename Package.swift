// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "ContextCard",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "ContextCard", targets: ["ContextCard"])
    ],
    targets: [
        .executableTarget(
            name: "ContextCard",
            resources: [.process("Resources")]
        ),
        .testTarget(name: "ContextCardTests", dependencies: ["ContextCard"])
    ]
)
