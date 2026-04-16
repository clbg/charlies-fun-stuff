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
