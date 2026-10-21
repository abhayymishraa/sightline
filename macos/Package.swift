// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "Sightline",
    platforms: [.macOS(.v14)],
    targets: [
        // Pure gaze math: no AppKit, no camera. Exercised by `swift run selfcheck`.
        .target(name: "GazeCore"),
        .executableTarget(name: "Sightline", dependencies: ["GazeCore"]),
        .executableTarget(name: "selfcheck", dependencies: ["GazeCore"]),
    ]
)
