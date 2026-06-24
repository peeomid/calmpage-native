// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "CalmPageNativeApp",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "CalmPageNative", targets: ["CalmPageNative"])
    ],
    targets: [
        .executableTarget(
            name: "CalmPageNative",
            path: "Sources/CalmPageNative",
            linkerSettings: [.linkedLibrary("sqlite3")]
        ),
        .testTarget(
            name: "CalmPageNativeTests",
            dependencies: ["CalmPageNative"],
            path: "Tests/CalmPageNativeTests"
        )
    ]
)
