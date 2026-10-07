// swift-tools-version: 5.10
// Assembled, not built in place: `Scripts/store-frames.sh` copies this
// package plus the Shared/ and widget sources it renders into a scratch
// folder and builds there. See CLAUDE.md in this folder.
import PackageDescription

let package = Package(
    name: "StoreFrames",
    platforms: [.macOS(.v14)],
    dependencies: [.package(path: "../../Packages/UsageKit")],
    targets: [
        .executableTarget(
            name: "StoreFrames",
            dependencies: ["UsageKit"],
            path: "Sources",
            resources: [.process("Media.xcassets")]
        )
    ]
)
