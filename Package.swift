// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Cogito",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(url: "https://github.com/ml-explore/mlx-swift-lm", from: "2.31.3"),
    ],
    targets: [
        .executableTarget(
            name: "Cogito",
            dependencies: [
                .product(name: "MLXLLM", package: "mlx-swift-lm"),
                .product(name: "MLXLMCommon", package: "mlx-swift-lm"),
            ],
            path: "Sources/Cogito"
        ),
        .executableTarget(
            name: "LLMTest",
            dependencies: [
                .product(name: "MLXLLM", package: "mlx-swift-lm"),
                .product(name: "MLXLMCommon", package: "mlx-swift-lm"),
            ],
            path: "Sources/LLMTest"
        )
    ]
)
