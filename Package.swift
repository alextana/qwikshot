// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "Qwikshot",
    platforms: [.macOS(.v15)],
    targets: [
        .executableTarget(name: "Qwikshot", path: "Sources/Qwikshot")
    ],
    swiftLanguageModes: [.v5]
)
