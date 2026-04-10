// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Cogito",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "Cogito",
            path: "Sources/Cogito"
        )
    ]
)
