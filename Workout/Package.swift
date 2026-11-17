// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Workout",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "Workout",
            path: "Sources/Workout"
        )
    ]
)
