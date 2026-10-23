import Foundation
import MosaicEngine
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
        // A bow tie: the bigger triangle stays, cut where the sides cross.
        let tie: [SIMD2<Double>] = [SIMD2(0, 0), SIMD2(10, 10), SIMD2(10, 0), SIMD2(0, 4)]
        let kept = MosaicCore.simple(tie, snap: { $0 })!
        #expect(kept.count == 3 && MosaicCore.firstSelfContact(kept) == nil)
        #expect(kept.contains(SIMD2(10, 10)) && kept.contains(SIMD2(10, 0)))
        // A spike (out and straight back) goes; so do a repeated point and one on a straight run.
        let spiked: [SIMD2<Double>] = [SIMD2(0, 0), SIMD2(5, 0), SIMD2(10, 0), SIMD2(10, 10), SIMD2(10, 10), SIMD2(5, 10),
                                       SIMD2(5, 15), SIMD2(5, 10), SIMD2(0, 10)]
        #expect(MosaicCore.simple(spiked, snap: { $0 }) == [SIMD2(0, 0), SIMD2(10, 0), SIMD2(10, 10), SIMD2(0, 10)])
        // Folded twice: still one simple loop (it may cover a lobe the fold had cancelled out).
        let lobed: [SIMD2<Double>] = [SIMD2(3, 4), SIMD2(4, 2), SIMD2(3, 1), SIMD2(3, 6), SIMD2(2, 5), SIMD2(1, 3), SIMD2(4, 1), SIMD2(6, 3)]
        let kept2 = MosaicCore.simple(lobed, snap: { $0 })!
        #expect(kept2.count >= 3 && MosaicCore.firstSelfContact(kept2) == nil)
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

    static func square(_ x0: Float, _ y0: Float, _ x1: Float, _ y1: Float, paint: Int = 0) -> Mosaic.Tile {
        Mosaic.Tile(corners: [SIMD2(x0, y0), SIMD2(x1, y0), SIMD2(x1, y1), SIMD2(x0, y1)], paint: paint)
    }

    @Test func aPupilNearTheLidStaysClearOfIt() throws {
        // The engine's test face with its eye looking up: the pupil 2 px under the upper lid.
        var face = MosaicEngine.Face(box: [14, 10, 56, 48], eyes: [[34, 24, 5, 2]],
                                     lines: [.init(kind: "eye", pts: [[26, 25], [30, 22.5], [36, 22], [42, 25], [36, 32], [30, 32], [26, 25]])])
        face.box = [14, 10, 56, 48]
        let w = 96, h = 64
        var rgb = [SIMD3<Float>](repeating: SIMD3(0.85, 0.75, 0.55), count: w * h)
        for y in 0..<h { for x in 0..<w where (Float(x) - 34) * (Float(x) - 34) + (Float(y) - 24) * (Float(y) - 24) < 25 { rgb[y * w + x] = SIMD3(0.45, 0.55, 0.65) } }
        var settings = MosaicEngine.Settings()
        settings.paints = 8
        let m = try MosaicEngine.make(photo: .init(width: w, height: h, rgb: rgb), contours: [Float](repeating: 0, count: w * h),
                                      faces: [face], settings: settings)
        let t = try MosaicCore.template(of: m)
        let report = t.validate(minLabelRadius: LabelSizing.minimumRadius)
        #expect(report.isValid, "\(report)")
    }

    @Test func anIrisRoundItsPupilGetsTheRoomItsRingHas() throws {
        // A pupil leaving its iris a thin ring: the canvas grows for the ring, not the whole square.
        let m = Mosaic(width: 100, height: 100, grout: SIMD3(0.9, 0.9, 0.9), palette: [SIMD3(0.2, 0.3, 0.6), SIMD3(0.1, 0.1, 0.1)],
                       tiles: [Self.square(10, 10, 12, 12), Self.square(10.05, 10.05, 11.95, 11.95, paint: 1)])
        let t = try MosaicCore.template(of: m)
        #expect(t.width > MosaicCore.templateLongSide)
        let report = t.validate(minLabelRadius: LabelSizing.minimumRadius)
        #expect(report.isValid, "\(report)")
    }

    @Test func nestedTilesAreHitInnermost() throws {
        // Three deep, the innermost with a lower index than the one it lies in.
        let m = Mosaic(width: 40, height: 40, grout: SIMD3(0.9, 0.9, 0.9), palette: [SIMD3(0.2, 0.3, 0.6)],
                       tiles: [Self.square(2, 2, 38, 38), Self.square(16, 16, 24, 24), Self.square(8, 8, 32, 32)])
        let t = try MosaicCore.template(of: m, longSide: 400)
        #expect(t.validate(minLabelRadius: LabelSizing.minimumRadius).isValid)
        #expect(t.regionMap[200, 200] == 1 && t.regionMap[100, 100] == 2 && t.regionMap[40, 40] == 0 && t.regionMap[5, 5] == 3)
    }

    @Test func aLongerSideIsKept() throws {
        let t = try MosaicCore.template(of: Self.small(), longSide: 5000)
        #expect(t.width == 5000)
    }

    /// Every bundled mosaic at every detail, in an optimized build (`swift test -c release`: about a
    /// minute); CI's unoptimized run takes the smallest, a face at its fewest pieces.
    static let bundled: [String] = {
        #if DEBUG
        ["young-woman-in-red-fewer"]
        #else
        ["bearded-man", "boy-eutyches", "elderly-lady", "hodegetria", "man-with-a-mole", "mother-and-child-gold-glass",
         "william", "young-woman-gilded-wreath", "young-woman-in-red"]
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
