// swift-tools-version: 6.1
import PackageDescription

let package = Package(
    name: "CharlieWidget",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "CharlieWidgetApp", targets: ["CharlieWidgetApp"]),
        .executable(name: "charlie-widget", targets: ["charlie-widget"]),
        .executable(name: "llm-smoke", targets: ["llm-smoke"]),
        .library(name: "CharlieLLM", targets: ["CharlieLLM"]),
    ],
    dependencies: [
        .package(url: "https://github.com/argmaxinc/argmax-oss-swift.git", from: "0.9.0"),
    ],
    targets: [
        .executableTarget(
            name: "CharlieWidgetApp",
            dependencies: [
                .product(name: "WhisperKit", package: "argmax-oss-swift"),
                "CharlieLLM",
            ],
            path: "Sources/CharlieWidgetApp",
            exclude: ["Resources"],
            linkerSettings: [
                .unsafeFlags([
                    "-Xlinker", "-sectcreate",
                    "-Xlinker", "__TEXT",
                    "-Xlinker", "__info_plist",
                    "-Xlinker", "Sources/CharlieWidgetApp/Resources/Info.plist"
                ])
            ]
        ),
        .executableTarget(
            name: "charlie-widget",
            path: "Sources/charlie-widget"
        ),
        // Shared LLM client (Bedrock / Anthropic API / OpenAI-compatible). Foundation + CryptoKit + Security only.
        .target(
            name: "CharlieLLM",
            path: "Sources/CharlieLLM"
        ),
        // Manual smoke tests + TTFT benchmarks for CharlieLLM.
        .executableTarget(
            name: "llm-smoke",
            dependencies: ["CharlieLLM"],
            path: "Sources/llm-smoke"
        ),
    ]
)
