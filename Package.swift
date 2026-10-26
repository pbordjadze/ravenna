// swift-tools-version: 6.2
import PackageDescription

// MosaicCore is Ravenna's engine: a photo laid as a Byzantine mosaic, built as an ordinary
// PaintCore template (one area per tile) so the painter can set it tile by tile. It is ported
// from the Python prototype (`prototype/`) and builds on Apple platforms and on Linux.
//
// PaintCore comes from paint-by-number at one commit, checked out by `tools/paintcore.sh` into
// `.deps/paint-by-number` (not committed): a path, never a version, since its targets use unsafe
// compiler flags, which SwiftPM refuses in a dependency resolved by version, and never the
// repository's URL, which SwiftPM would clone with every ref (many gigabytes of CI reports). The
// app's Xcode project links the same checkout, and `App/Ravenna` was copied from that commit's
// `App/PaintByNumber`. Move the pin on purpose, and say why in the commit.
let package = Package(
    name: "MosaicCore",
    platforms: [.iOS("18.0"), .macOS("15.0")],
    products: [
        .library(name: "MosaicKit", targets: ["MosaicKit"]),
        .library(name: "MosaicEngine", targets: ["MosaicEngine"]),
        .library(name: "MosaicCore", targets: ["MosaicCore"]),
    ],
    dependencies: [
        .package(path: ".deps/paint-by-number"),
    ],
    targets: [
        // The mosaic as the app sets it (tiles, finishes, the painter's progress): plain Swift with
        // no dependencies, tested on Linux.
        .target(name: "MosaicKit"),
        .testTarget(name: "MosaicKitTests", dependencies: ["MosaicKit"]),
        // The engine: a photo, its contours and its faces' features made into a Mosaic, ported from
        // `prototype/mosaic_faces.py`. Plain Swift on MosaicKit's types only; `mosaic` runs it on files
        // for comparison with the prototype.
        .target(name: "MosaicEngine", dependencies: ["MosaicKit"]),
        .testTarget(name: "MosaicEngineTests", dependencies: ["MosaicEngine", "MosaicKit"]),
        .executableTarget(name: "mosaic", dependencies: ["MosaicEngine", "MosaicKit"]),
        .target(
            name: "MosaicCore",
            dependencies: ["MosaicKit", .product(name: "PaintCore", package: "paint-by-number")]
        ),
        .testTarget(
            name: "MosaicCoreTests",
            dependencies: ["MosaicCore", "MosaicKit", "MosaicEngine", .product(name: "PaintCore", package: "paint-by-number")]
        ),
    ],
    swiftLanguageModes: [.v6]
)
