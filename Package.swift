// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Cogito",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(url: "https://github.com/ml-explore/mlx-swift-lm", branch: "main"),
        .package(url: "https://github.com/DePasqualeOrg/swift-hf-api", from: "0.2.2"),
        .package(url: "https://github.com/DePasqualeOrg/swift-tokenizers", from: "0.3.2"),
    ],
    targets: [
        .target(
            name: "MLXBridge",
            dependencies: [
                .product(name: "MLXLMCommon", package: "mlx-swift-lm"),
                .product(name: "HFAPI", package: "swift-hf-api"),
                .product(name: "Tokenizers", package: "swift-tokenizers"),
            ],
            path: "Sources/MLXBridge"
        ),
        .executableTarget(
            name: "Cogito",
            dependencies: [
                "MLXBridge",
                .product(name: "MLXLLM", package: "mlx-swift-lm"),
                .product(name: "MLXLMCommon", package: "mlx-swift-lm"),
                .product(name: "HFAPI", package: "swift-hf-api"),
            ],
            path: "Sources/Cogito"
        ),
        .executableTarget(
            name: "LLMTest",
            dependencies: [
                "MLXBridge",
                .product(name: "MLXLLM", package: "mlx-swift-lm"),
                .product(name: "MLXLMCommon", package: "mlx-swift-lm"),
                .product(name: "HFAPI", package: "swift-hf-api"),
            ],
            path: "Sources/LLMTest"
        )
    ]
)
