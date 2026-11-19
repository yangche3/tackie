// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Tackie",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "Tackie",
            path: "Sources/Tackie"
        )
    ]
)
