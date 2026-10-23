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

    @Test(arguments: ["bearded-man", "boy-eutyches", "william", "young-woman-gilded-wreath", "young-woman-in-red"])
    func eachBundledMosaicValidates(_ id: String) throws {
        for detail in ["fewer", "standard", "more"] {
            let m = try JSONDecoder().decode(Mosaic.self, from: Data(contentsOf: Self.mosaics.appendingPathComponent("\(id)-\(detail).json")))
            let t = try MosaicCore.template(of: m)
            let report = t.validate(minLabelRadius: LabelSizing.minimumRadius)
            #expect(report.isValid, "\(id)-\(detail): \(report)")
            #expect(t.regions.count == m.tiles.count + 1)
            #expect(t.regions.last!.labelCount > 1, "\(id)-\(detail): the grout numbered across the canvas")
            #expect(!t.isDetailRegion(m.tiles.count), "\(id)-\(detail): the grout has room for its number")
            let tilesInDetail = t.detailRegions.count
            #expect(Double(tilesInDetail) < 0.03 * Double(m.tiles.count), "\(id)-\(detail): \(tilesInDetail) tiles read zoomed in")
            print("\(id)-\(detail): \(m.tiles.count) tiles, \(tilesInDetail) detail areas, \(t.regions.last!.labelCount) grout labels, room \(report.minLabelRoom)")
        }
    }
}
