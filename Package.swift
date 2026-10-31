// swift-tools-version:6.2
import PackageDescription

let package = Package(
    name: "Qwikshot",
    platforms: [.macOS(.v26)],
    dependencies: [
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.10.1")
    ],
    targets: [
        .executableTarget(
            name: "Qwikshot",
            dependencies: [.product(name: "Sparkle", package: "Sparkle")],
            path: "Sources/Qwikshot",
            linkerSettings: [.unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks"])]
        )
    ],
    swiftLanguageModes: [.v5]
)
