// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "DoriCall",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(name: "DoriCall", path: "Sources/DoriCall")
    ]
)
