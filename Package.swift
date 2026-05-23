// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "MacTaskbar",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "MacTaskbar",
            path: "Sources/MacTaskbar"
        )
    ]
)
