// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "SeasonArt",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "SeasonArt", targets: ["SeasonArt"]),
    ],
    targets: [
        .executableTarget(name: "SeasonArt", path: "Sources/SeasonArt"),
    ]
)
