// swift-tools-version: 5.9

// Suggests A1 theme words from seed words with Quiver's EmbeddingIndex.
// A tool for authors' machines; the app never links it.

import PackageDescription

let package = Package(
    name: "ThemeExpander",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(url: "https://github.com/waynewbishop/quiver", from: "1.6.0")
    ],
    targets: [
        .executableTarget(
            name: "ThemeExpander",
            dependencies: [.product(name: "Quiver", package: "quiver")]
        )
    ]
)
