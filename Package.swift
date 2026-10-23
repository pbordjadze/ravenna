// swift-tools-version: 6.2
import PackageDescription

// MosaicCore is Ravenna's engine: a photo laid as a Byzantine mosaic, built as an ordinary
// PaintCore template (one area per tile) so the painter can set it tile by tile. It is ported
// from the Python prototype (`prototype/`) and builds on Apple platforms and on Linux.
//
// PaintCore is pinned by revision, never by version: its targets use unsafe compiler flags,
// which SwiftPM refuses in a dependency resolved by version. Move the pin on purpose.
let package = Package(
    name: "MosaicCore",
    platforms: [.iOS("18.0"), .macOS("15.0")],
    products: [
        .library(name: "MosaicCore", targets: ["MosaicCore"]),
    ],
    dependencies: [
        .package(
            url: "https://github.com/pbordjadze/paint-by-number",
            revision: "d3e3a9549ed9140f1adb55b07352800f35c96a78"
        ),
    ],
    targets: [
        .target(
            name: "MosaicCore",
            dependencies: [.product(name: "PaintCore", package: "paint-by-number")]
        ),
        .testTarget(
            name: "MosaicCoreTests",
            dependencies: ["MosaicCore", .product(name: "PaintCore", package: "paint-by-number")]
        ),
    ],
    swiftLanguageModes: [.v6]
)
