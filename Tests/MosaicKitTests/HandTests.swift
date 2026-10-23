import Foundation
import Testing
@testable import MosaicKit

/// A row of four square tiles, paints 0, 0, 1, 0; and the hand that lays them.
@Suite("The hand")
struct HandTests {
    static func row() -> Mosaic {
        let tiles = (0..<4).map { k in
            let x = Float(k * 10)
            return Mosaic.Tile(corners: [SIMD2(x + 1, 1), SIMD2(x + 9, 1), SIMD2(x + 9, 9), SIMD2(x + 1, 9)], paint: k == 2 ? 1 : 0)
        }
        return Mosaic(width: 40, height: 10, grout: SIMD3(0.8, 0.8, 0.8), palette: [SIMD3(0.2, 0.3, 0.6), SIMD3(0.8, 0.65, 0.25)], tiles: tiles)
    }

    @Test func aStrokeAlongARowMeetsItsTilesInOrder() {
        let m = Self.row(), index = TileIndex(m)
        #expect(index.tiles(along: SIMD2(2, 5), SIMD2(38, 5), step: 2) == [0, 1, 2, 3])
        #expect(index.tiles(along: SIMD2(38, 5), SIMD2(2, 5), step: 2) == [3, 2, 1, 0], "backwards")
        #expect(index.tiles(along: SIMD2(5, 5), SIMD2(15, 5), step: 2) == [0, 1], "the tile it starts on, as soon as it moves")
        #expect(index.tiles(along: SIMD2(2, 5), SIMD2(38, 5), step: 100) == [3], "a step too long skips tiles")
        #expect(index.tiles(along: SIMD2(5, 5), SIMD2(5, 5), step: 2) == [0], "a stroke that hasn't moved")
    }

    @Test func aStrokeLaysOnlyThePaintInHand() {
        let m = Self.row(), index = TileIndex(m)
        var s = Setting()
        s.place(1, with: 0, in: m)
        let passed = index.tiles(along: SIMD2(0, 5), SIMD2(40, 5), step: 2)
        #expect(s.laying(passed, with: 0, in: m) == [0, 3], "not the gold, not the one already set")
        #expect(s.laying([0, 0, 3, 0], with: 0, in: m) == [0, 3], "each once")
        #expect(s.laying([9], with: 0, in: m).isEmpty)
    }

    @Test func theNearestUnsetTile() {
        let m = Self.row()
        var s = Setting()
        #expect(s.nearestUnset(of: 0, to: SIMD2(28, 5), in: m) == 3)
        s.place(3, with: 0, in: m)
        #expect(s.nearestUnset(of: 0, to: SIMD2(28, 5), in: m) == 1)
        #expect(s.nearestUnset(of: 1, to: SIMD2(0, 0), in: m) == 2)
        s.place(2, with: 1, in: m)
        #expect(s.nearestUnset(of: 1, to: SIMD2(0, 0), in: m) == nil)
    }

    @Test func aTileSettlesAndCatchesTheLightOnce() {
        #expect(Motion.settled(0) == 0 && Motion.settled(Motion.press) == 0, "held raised")
        #expect(Motion.settled(Motion.press + Motion.settle) == 1)
        let curve = stride(from: 0.0, through: Motion.total, by: 0.005).map(Motion.settled)
        #expect(curve.max()! > 1 && curve.max()! < 1.08, "overshoots by a hair")
        #expect(Motion.glinting(Motion.glintStart - 0.01) == nil && Motion.glinting(Motion.glintStart + 0.1) != nil)
        #expect(Motion.glintStart + Motion.glint <= Motion.total && Motion.contact < Motion.press + Motion.settle)
        #expect(Motion.fade(0) == 0 && Motion.fade(1) == 1)
    }

    @Test func lightComesFromTheUpperLeft() {
        let square: [SIMD2<Float>] = [SIMD2(0, 0), SIMD2(1, 0), SIMD2(1, 1), SIMD2(0, 1)]
        let cw = Light.clockwise(square)
        #expect(cw, "on screen, with y down")
        #expect(Light.edge(square[0], square[1], clockwise: cw) > 0.7, "the top edge is lit")
        #expect(Light.edge(square[2], square[3], clockwise: cw) < -0.7, "the bottom is in shade")
        let ccw = Array(square.reversed())
        #expect(!Light.clockwise(ccw) && Light.edge(ccw[2], ccw[3], clockwise: false) > 0.7, "either winding")
        #expect(Light.litCorner(square) == 0)
    }

    @Test func eachVoiceIsAClinkThatDiesAway() {
        for v in Voice.allCases {
            let s = v.clink(frequency: 440)
            #expect(s.allSatisfy { abs($0) <= 1 })
            let early = s[0..<2000].map { abs($0) }.max()!, late = s[(s.count - 500)...].map { abs($0) }.max()!
            #expect(early > 0.1 && late < early * 0.1, "\(v): a clink that dies away")
            #expect(s == v.clink(frequency: 440), "deterministic")
        }
        #expect(Voice.stone.clink(frequency: 440).count < Voice.glass.clink(frequency: 440).count, "stone is drier")
        let m = Self.row()
        #expect(Voice.of(m.tiles[2], in: m) == .gold && Voice.of(m.tiles[0], in: m) == .glass)
    }

    @Test func theTunePlaysOnAndBreathes() {
        var m = Melody()
        let t0 = Date(timeIntervalSinceReferenceDate: 0)
        let first = (0..<8).map { m.next(at: t0.addingTimeInterval(Double($0) * 0.1)).index }
        #expect(first == Array(Melody.tune[0..<8]))
        #expect(m.latest == Melody.tune[7])
        _ = m.next(at: t0.addingTimeInterval(1))
        // Mid-phrase, a long pause: the tune picks up at the next phrase.
        let after = m.next(at: t0.addingTimeInterval(10))
        #expect(after.index == Melody.tune[16] && m.position == 17)
        // Round the whole tune and back to the start.
        var n = Melody()
        for k in 0..<Melody.tune.count { _ = n.next(at: t0.addingTimeInterval(Double(k) * 0.1)) }
        #expect(n.position == 0)
        #expect(Melody.Mode.allCases.allSatisfy { $0.scale.count == 12 && $0.scale.count > Melody.tune.max()! })
        #expect(Melody.Mode.minor.scale[1] == Melody.Mode.major.scale[0], "the minor is the same notes, from the B below")
    }
}
