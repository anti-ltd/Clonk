// swift-tools-version: 6.1
import PackageDescription

let package = Package(
    name: "Clonk",
    platforms: [.macOS("26.0")],
    products: [
        // Import ClonkCore to embed Clonk in a bundle app without its icon
        // or menu-bar item. The public surface is ClonkModule.
        .library(name: "ClonkCore", targets: ["ClonkCore"]),
        // The standalone Clonk.app — built via `make app`.
        .executable(name: "Clonk", targets: ["Clonk"]),
    ],
    dependencies: [
        // Shared UX layer — settings popover, menu-bar host and overlay windows.
        .package(path: "../iUX-MacOS"),
    ],
    targets: [
        // All business logic, DSP, and settings UI. No icon, no menu-bar item.
        .target(
            name: "ClonkCore",
            dependencies: ["iUX-MacOS"],
            path: "Sources/ClonkCore"
        ),
        // Standalone entry point: AppDelegate, menu-bar controller, icon renderer.
        .executableTarget(
            name: "Clonk",
            dependencies: ["ClonkCore"],
            path: "Sources/Clonk"
        ),
        // Unit tests — pure logic only (no UI, no menu bar).
        .testTarget(
            name: "ClonkCoreTests",
            dependencies: ["ClonkCore"],
            path: "Tests/ClonkCoreTests"
        ),
    ]
)
