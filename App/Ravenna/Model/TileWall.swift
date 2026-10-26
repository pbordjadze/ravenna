import Foundation
import MosaicKit
import PaintCore

/// A painting that is a mosaic: its `MosaicKit.Mosaic` beside the template made of it
/// (`MosaicCore.template(of:)`), where region `i` is tile `i` and the last region is the grout.
/// What the canvas draws tiles from (`CanvasScene`), what a drag lays a row with
/// (`PaintingSession.drag`) and what the sounds and taps are weighed by (`FeedbackEngine`).
///
/// The grout is the ground, not something to paint: a session sets it before the painter's first
/// tile (`PaintingSession.make`), undo never lifts it and the canvas draws it as the bed.
nonisolated struct TileWall: Sendable {
    let mosaic: Mosaic
    /// Template units per mosaic unit: the template is the mosaic scaled up to PaintCore's range.
    let scale: Float
    let index: TileIndex
    /// Per tile: what it sounds like going in, and how heavy it is against a middling tile (0...1).
    let voices: [Voice]
    let weights: [Float]
    /// Per tile: whether its paint is gold smalti (`TileColor.isGold`).
    let gold: [Bool]

    /// The grout's region in the template.
    var groutRegion: Int { mosaic.tiles.count }

    /// Nil unless `template` is `mosaic`'s: a region per tile and one for the grout.
    init?(mosaic: Mosaic, template: Template) {
        guard !mosaic.tiles.isEmpty, mosaic.width > 0, template.regions.count == mosaic.tiles.count + 1 else { return nil }
        self.mosaic = mosaic
        scale = Float(template.width) / mosaic.width
        index = TileIndex(mosaic)
        voices = mosaic.tiles.map { Voice.of($0, in: mosaic) }
        let golds = mosaic.palette.map(TileColor.isGold)
        gold = mosaic.tiles.map { golds[$0.paint] }
        let sides = mosaic.tiles.map { t -> Float in
            let (lo, hi) = t.bounds
            return ((hi.x - lo.x) * (hi.y - lo.y)).squareRoot()
        }
        let typical = max(sides.sorted()[sides.count / 2], 0.01)
        weights = sides.map { min(max($0 / typical * 0.6, 0), 1) }
    }

    /// Whether `region` is a tile (not the grout).
    func isTile(_ region: Int) -> Bool { region >= 0 && region < mosaic.tiles.count }

    /// The tiles of `paint` not yet painted that a finger moving from `a` to `b` (template units)
    /// passes over, in the order it meets them: a row laid in one movement (MosaicKit's `Laying`).
    /// `radius` is the finger's, and sets how finely the stroke is sampled and how near a tile's
    /// centre a fingertip in a joint still counts.
    func laying(from a: SIMD2<Float>, to b: SIMD2<Float>, radius: Float, paint: Int, isPainted: (Int) -> Bool) -> [Int] {
        let k = 1 / scale
        // v0's 3 and 4 points against its 11 point finger.
        let passed = index.tiles(along: a * k, b * k, step: radius * k * 0.27, slop: radius * k * 0.36)
        var seen = Set<Int>()
        return passed.filter { mosaic.tiles[$0].paint == paint && !isPainted($0) && seen.insert($0).inserted }
    }
}
