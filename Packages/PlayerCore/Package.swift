// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "PlayerCore",
    platforms: [.tvOS(.v18), .iOS(.v18), .macOS(.v15)],
    products: [.library(name: "PlayerCore", targets: ["PlayerCore"])],
    targets: [
        .target(name: "PlayerCore"),
        .testTarget(name: "PlayerCoreTests", dependencies: ["PlayerCore"], resources: [.copy("Fixtures")]),
    ]
)
