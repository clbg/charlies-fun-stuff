// swift-tools-version: 6.1
import PackageDescription

let package = Package(
    name: "CharlieWidget",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "CharlieWidgetApp", targets: ["CharlieWidgetApp"]),
        .executable(name: "charlie-widget", targets: ["charlie-widget"]),
    ],
    targets: [
        .executableTarget(
            name: "CharlieWidgetApp",
            path: "Sources/CharlieWidgetApp"
        ),
        .executableTarget(
            name: "charlie-widget",
            path: "Sources/charlie-widget"
        ),
    ]
)
