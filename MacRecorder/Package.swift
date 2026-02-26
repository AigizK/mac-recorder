// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "MacRecorder",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "MacRecorder",
            path: "Sources",
            resources: [.process("../Resources")]
        ),
    ]
)
