// swift-tools-version: 5.10
// Records the website's notch island videos (see CLAUDE.md here): the
// running app's island captured alone, composed over a drawn desktop.
import PackageDescription

let package = Package(
    name: "IslandVideo",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(name: "IslandVideo", path: "Sources")
    ]
)
