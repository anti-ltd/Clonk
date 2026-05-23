// swift-tools-version: 6.1
import PackageDescription

let package = Package(
    name: "Clonk",
    platforms: [.macOS("26.0")],
    dependencies: [
        // Shared UX layer — settings popover, menu-bar host and overlay windows.
        .package(path: "../iUX"),
    ],
    targets: [
        .executableTarget(
            name: "Clonk",
            dependencies: ["iUX"],
            path: "Sources/Clonk"
        )
    ]
)
