// swift-tools-version: 6.1
import PackageDescription

let package = Package(
    name: "Clonk",
    platforms: [.macOS("26.0")],
    targets: [
        .executableTarget(
            name: "Clonk",
            path: "Sources/Clonk"
        )
    ]
)
