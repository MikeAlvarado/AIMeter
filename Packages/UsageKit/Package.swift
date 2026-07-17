// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "UsageKit",
    platforms: [
        .iOS(.v17),
        .macOS(.v14),
    ],
    products: [
        .library(name: "UsageKit", targets: ["UsageKit"]),
    ],
    targets: [
        .target(name: "UsageKit"),
        .testTarget(
            name: "UsageKitTests",
            dependencies: ["UsageKit"],
            resources: [.copy("Fixtures")]
        ),
    ]
)
