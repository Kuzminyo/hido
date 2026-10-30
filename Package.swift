// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "Hido",
    platforms: [.macOS(.v26)],
    targets: [
        // Objective-C, so exceptions from the private menu bar API can be caught.
        .target(name: "HidoShim", path: "Sources/HidoShim"),
        .executableTarget(
            name: "Hido",
            dependencies: ["HidoShim"],
            path: "Sources/Hido",
            swiftSettings: [.swiftLanguageMode(.v5)]
        )
    ]
)
