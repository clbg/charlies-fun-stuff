// swift-tools-version: 6.1
import PackageDescription

let package = Package(
    name: "CharlieWidget",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "CharlieWidgetApp", targets: ["CharlieWidgetApp"]),
        .executable(name: "charlie-widget", targets: ["charlie-widget"]),
    ],
    dependencies: [
        .package(url: "https://github.com/argmaxinc/argmax-oss-swift.git", from: "0.9.0"),
    ],
    targets: [
        .executableTarget(
            name: "CharlieWidgetApp",
            dependencies: [
                .product(name: "WhisperKit", package: "argmax-oss-swift"),
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
    ]
)
