// swift-tools-version: 6.1
import PackageDescription

let package = Package(
    name: "AgentOperator",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "AgentOperatorApp", targets: ["AgentOperatorApp"]),
        .executable(name: "agent-operator", targets: ["agent-operator"]),
    ],
    dependencies: [
        .package(url: "https://github.com/argmaxinc/argmax-oss-swift.git", from: "0.9.0"),
    ],
    targets: [
        .executableTarget(
            name: "AgentOperatorApp",
            dependencies: [
                .product(name: "WhisperKit", package: "argmax-oss-swift"),
            ],
            path: "Sources/AgentOperatorApp",
            exclude: ["Resources"],
            linkerSettings: [
                .unsafeFlags([
                    "-Xlinker", "-sectcreate",
                    "-Xlinker", "__TEXT",
                    "-Xlinker", "__info_plist",
                    "-Xlinker", "Sources/AgentOperatorApp/Resources/Info.plist"
                ])
            ]
        ),
        .executableTarget(
            name: "agent-operator",
            path: "Sources/agent-operator"
        ),
    ]
)
