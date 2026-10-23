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
        .library(name: "MosaicKit", targets: ["MosaicKit"]),
        .library(name: "MosaicCore", targets: ["MosaicCore"]),
    ],
    dependencies: [
        .package(
            url: "https://github.com/pbordjadze/paint-by-number",
            revision: "d3e3a9549ed9140f1adb55b07352800f35c96a78"
        ),
    ],
    targets: [
        // The mosaic as the app sets it (tiles, finishes, the painter's progress): plain Swift with
        // no dependencies, so the app compiles these files directly (App/Ravenna.xcodeproj) without
        // resolving PaintCore, and Linux tests them.
        .target(name: "MosaicKit"),
        .testTarget(name: "MosaicKitTests", dependencies: ["MosaicKit"]),
        // The engine: a photo, its contours and its faces' features made into a Mosaic, ported from
        // `prototype/mosaic_faces.py`. Plain Swift on MosaicKit's types only, so the app compiles
        // these files directly too; `mosaic` runs it on files for comparison with the prototype.
        .target(name: "MosaicEngine", dependencies: ["MosaicKit"]),
        .testTarget(name: "MosaicEngineTests", dependencies: ["MosaicEngine", "MosaicKit"]),
        .executableTarget(name: "mosaic", dependencies: ["MosaicEngine", "MosaicKit"]),
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
