// swift-tools-version:6.2
import PackageDescription

let package = Package(
    name: "Qwikshot",
    platforms: [.macOS(.v26)],
    targets: [
        .executableTarget(name: "Qwikshot", path: "Sources/Qwikshot")
    ],
    swiftLanguageModes: [.v5]
)
