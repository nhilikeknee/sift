// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Sift",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "Sift",
            path: "Sift",
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .testTarget(
            name: "SiftTests",
            dependencies: ["Sift"],
            path: "Tests/SiftTests",
            // Read from the source tree by path, not copied into the bundle:
            // the tests already locate the repo root from `#filePath`.
            exclude: ["Fixtures"],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
    ]
)
