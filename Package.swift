// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "SeasonArt",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "SeasonArt", targets: ["SeasonArt"]),
    ],
    targets: [
        // Box2D v3.1.0 (MIT), исходники без изменений: физика снежков.
        .target(name: "CBox2D", path: "Sources/CBox2D", exclude: ["LICENSE"],
                cSettings: [.headerSearchPath("src"), .define("NDEBUG")]),
        .executableTarget(name: "SeasonArt", dependencies: ["CBox2D"], path: "Sources/SeasonArt"),
        .testTarget(name: "SeasonArtTests", dependencies: ["SeasonArt"]),
    ],
    cLanguageStandard: .c17
)
