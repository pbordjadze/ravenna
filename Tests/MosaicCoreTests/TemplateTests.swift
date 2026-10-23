import Foundation
import MosaicKit
import PaintCore
import Testing
@testable import MosaicCore

/// A mosaic as a PaintCore template (`MosaicCore.template(of:)`): exact tiles, one grout area, and
/// every number with its room, as `Template.validate` judges PaintCore's own templates.
@Suite("Template")
struct TemplateTests {
    static let mosaics = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("App/Ravenna/Resources/Mosaics")

    /// Two squares and a triangle on a 40 × 20 canvas.
    static func small() -> Mosaic {
        let tiles = [
            Mosaic.Tile(corners: [SIMD2(2, 2), SIMD2(12, 2), SIMD2(12, 12), SIMD2(2, 12)], paint: 0),
            Mosaic.Tile(corners: [SIMD2(14, 2), SIMD2(24, 2), SIMD2(24, 12), SIMD2(14, 12)], paint: 1),
            Mosaic.Tile(corners: [SIMD2(27, 18), SIMD2(37, 18), SIMD2(32, 3)], paint: 0),   // anticlockwise on screen
        ]
        return Mosaic(width: 40, height: 20, grout: SIMD3(0.86, 0.84, 0.8), palette: [SIMD3(0.2, 0.3, 0.6), SIMD3(0.8, 0.65, 0.25)], tiles: tiles)
    }

    @Test func aSmallMosaicIsItsTilesAndTheGrout() throws {
        let m = Self.small()
        let t = try MosaicCore.template(of: m, longSide: 80)
        #expect(t.width == 80 && t.height == 40)
        #expect(t.regions.count == 4 && t.palette.count == 3)
        #expect(t.regions.map(\.colorIndex) == [0, 1, 0, 2], "the tiles' paints, then the grout's")
        #expect(t.regions[0].area == 400)
        let total: Float = t.regions.map(\.area).reduce(0, +)
        #expect(abs(total - 3200) < 1e-2)
        #expect(t.regions[3].ringCount == 4, "the grout: the border and a hole per tile")
        #expect(t.regionMap[10, 10] == 0 && t.regionMap[38, 10] == 1 && t.regionMap[1, 1] == 3)
        let report = t.validate(minLabelRadius: LabelSizing.minimumRadius)
        #expect(report.isValid, "\(report)")
        #expect(try Template(encoded: t.encoded()) == t)
    }

    @Test func aTileWithNoAreaIsAnError() {
        var m = Self.small()
        m.tiles[1].corners = [SIMD2(14, 2), SIMD2(24, 2), SIMD2(19, 2)]
        #expect(throws: MosaicCore.TemplateError.degenerateTile(1)) { try MosaicCore.template(of: m) }
    }

    @Test func aFoldedOutlineKeepsItsBiggestLoop() {
        // A bow tie: the bigger triangle stays, cut where the sides cross, inside the tile as laid.
        let tie: [SIMD2<Double>] = [SIMD2(0, 0), SIMD2(10, 10), SIMD2(10, 0), SIMD2(0, 4)]
        let kept = MosaicCore.simple(tie, snap: { $0 })!
        #expect(kept.count == 3 && MosaicCore.firstSelfContact(kept) == nil)
        #expect(kept.contains(SIMD2(10, 10)) && kept.contains(SIMD2(10, 0)))
        // A spike (out and straight back) goes; so do a repeated point and one on a straight run.
        let spiked: [SIMD2<Double>] = [SIMD2(0, 0), SIMD2(5, 0), SIMD2(10, 0), SIMD2(10, 10), SIMD2(10, 10), SIMD2(5, 10),
                                       SIMD2(5, 15), SIMD2(5, 10), SIMD2(0, 10)]
        #expect(MosaicCore.simple(spiked, snap: { $0 }) == [SIMD2(0, 0), SIMD2(10, 0), SIMD2(10, 10), SIMD2(0, 10)])
        // Nothing with area: nil.
        #expect(MosaicCore.simple([SIMD2(0, 0), SIMD2(4, 0), SIMD2(8, 0)], snap: { $0 }) == nil)
    }

    /// The tiles of a bundled mosaic within `margin` of its eyes, moved to a canvas of their own.
    static func aroundTheEyes(_ name: String, margin: Float) throws -> Mosaic {
        let m = try JSONDecoder().decode(Mosaic.self, from: Data(contentsOf: mosaics.appendingPathComponent("\(name).json")))
        let eyes = m.tiles.filter { $0.stage == .eye }.flatMap(\.corners)
        let lo = eyes.reduce(SIMD2<Float>(repeating: .infinity)) { pointwiseMin($0, $1) } - margin
        let hi = eyes.reduce(SIMD2<Float>(repeating: -.infinity)) { pointwiseMax($0, $1) } + margin
        let tiles = m.tiles.filter { t in t.corners.allSatisfy { $0.x > lo.x && $0.y > lo.y && $0.x < hi.x && $0.y < hi.y } }
            .map { t in var t = t; t.corners = t.corners.map { $0 - lo }; return t }
        return Mosaic(width: hi.x - lo.x, height: hi.y - lo.y, grout: m.grout, palette: m.palette, tiles: tiles)
    }

    @Test func aPupilIsAHoleInItsIris() throws {
        let m = try Self.aroundTheEyes("boy-eutyches-more", margin: 40)
        let t = try MosaicCore.template(of: m, longSide: 1024)
        let report = t.validate(minLabelRadius: LabelSizing.minimumRadius)
        #expect(report.isValid, "\(report)")
        let eyes = m.tiles.indices.filter { m.tiles[$0].stage == .eye }
        #expect(eyes.count == 4)
        for iris in eyes.prefix(2) { #expect(t.regions[iris].ringCount == 2, "the iris has its pupil as a hole") }
        for pupil in eyes.suffix(2) {
            let edge = t.edges[Int(t.ringEdges[Int(t.rings[Int(t.regions[pupil].ringStart)].edgeStart)].edge)]
            #expect(eyes.prefix(2).contains(Int(edge.left)) && Int(edge.right) == pupil, "the pupil's edge is shared with its iris")
        }
        #expect(t.regions.last!.ringCount == UInt32(1 + m.tiles.count - 2), "the grout's holes: every tile but the pupils")
    }

    /// Every bundled mosaic at every detail, in an optimized build (`swift test -c release`: about a
    /// minute); CI's unoptimized run takes the smallest, a face at its fewest pieces.
    static let bundled: [String] = {
        #if DEBUG
        ["young-woman-in-red-fewer"]
        #else
        ["bearded-man", "boy-eutyches", "william", "young-woman-gilded-wreath", "young-woman-in-red"]
            .flatMap { id in ["fewer", "standard", "more"].map { "\(id)-\($0)" } }
        #endif
    }()

    @Test(arguments: bundled)
    func eachBundledMosaicValidates(_ name: String) throws {
        let m = try JSONDecoder().decode(Mosaic.self, from: Data(contentsOf: Self.mosaics.appendingPathComponent("\(name).json")))
        let t = try MosaicCore.template(of: m)
        let report = t.validate(minLabelRadius: LabelSizing.minimumRadius)
        #expect(report.isValid, "\(name): \(report)")
        #expect(t.regions.count == m.tiles.count + 1)
        #expect(t.regions.last!.labelCount > 1, "\(name): the grout numbered across the canvas")
        #expect(!t.isDetailRegion(m.tiles.count), "\(name): the grout has room for its number")
        #expect(Double(t.detailRegions.count) < 0.03 * Double(m.tiles.count), "\(name): \(t.detailRegions.count) tiles read zoomed in")
        #expect(max(t.width, t.height) <= MosaicCore.maximumLongSide)
    }
}
