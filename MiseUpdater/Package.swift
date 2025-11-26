// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "MiseUpdater",
    platforms: [
        .macOS(.v13)
    ],
    targets: [
        .executableTarget(
            name: "MiseUpdater",
            path: ".",
            sources: ["MiseUpdater.swift"]
        )
    ]
)
