// swift-tools-version: 6.1
import PackageDescription

// Hülle um AetherEngine mit eingeschaltetem Paket-Trait „DolbyVisionFelCurves“ (Dolby Vision FEL:
// Erweiterungsschicht eines Profile-7-FEL-Films als Kurven ins Profile-8.1-RPU des nativen Wegs).
// XcodeGen kann Traits nicht ausdrücken und Xcode übernahm eine Trait-Liste in der .pbxproj nicht;
// die Engine-Doku (installation.md, „Turning traits on“, Weg 2) nennt dafür dieses lokale Paket, das
// die Engine mit Trait einbindet und neu exportiert. Die App hängt an diesem Paket statt an der Engine.
let package = Package(
    name: "AetherFEL",
    platforms: [.tvOS(.v18), .iOS(.v18), .macOS(.v15), .visionOS(.v1)],
    products: [.library(name: "AetherFEL", targets: ["AetherFEL"])],
    dependencies: [
        // Genau dieser Stand (öffentliches Release; alle Player-Regeln sind gegen 7.71.2 geprüft).
        .package(
            url: "https://github.com/superuser404notfound/AetherEngine",
            exact: "7.71.2",
            // DolbyVisionStillReshaping (wave X0, user decision 22.11.): CPU reshaping of Dolby Vision Profile 5 /
            // AV1 10.0 frames into stills (scrub previews, X-Ray face probe); playback itself is meant to stay unchanged.
            traits: ["DolbyVisionFelCurves", "DolbyVisionStillReshaping"]
        ),
    ],
    targets: [
        .target(
            name: "AetherFEL",
            dependencies: [.product(name: "AetherEngine", package: "AetherEngine")]
        ),
    ]
)
