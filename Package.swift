// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "Hido",
    platforms: [.macOS(.v26)],
    targets: [
        .executableTarget(
            name: "Hido",
            path: "Sources/Hido",
            swiftSettings: [.swiftLanguageMode(.v5)]
        )
    ]
)
