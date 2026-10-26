import Foundation
import Testing
@testable import MosaicKit

/// Two square tiles side by side, a joint between them, two paints; the second tile stone.
@Suite("MosaicKit")
struct MosaicKitTests {
    static let json = #"""
    {"size":[20,10],"grout":[0.86,0.85,0.84],"palette":[[0.8,0.1,0.1],[0.83,0.68,0.24]],
     "tiles":[{"c":[1,1,9,1,9,9,1,9],"p":0},{"c":[11,1,19,1,19,9,11,9],"p":1,"s":1,"g":"row"}]}
    """#

    static func mosaic() throws -> Mosaic { try JSONDecoder().decode(Mosaic.self, from: Data(json.utf8)) }

    @Test func readsTheBundleFormat() throws {
        let m = try Self.mosaic()
        #expect(m.width == 20 && m.height == 10 && m.palette.count == 2 && m.tiles.count == 2)
        #expect(m.tiles[0].corners == [SIMD2(1, 1), SIMD2(9, 1), SIMD2(9, 9), SIMD2(1, 9)])
        #expect(!m.tiles[0].stone && m.tiles[1].stone)
        #expect(m.tiles[0].stage == nil && m.tiles[1].stage == .row, "the stage is optional: older files have none")
        #expect(m.tiles[1].centre == SIMD2(15, 5))
        #expect(m.tilesPerPaint == [1, 1])
        let again = try JSONDecoder().decode(Mosaic.self, from: JSONEncoder().encode(m))
        #expect(again == m)
    }

    @Test func refusesATileWithAPaintItDoesNotHave() {
        let bad = Self.json.replacingOccurrences(of: #""p":1"#, with: #""p":5"#)
        #expect(throws: Mosaic.FormatError.badTile(1)) { try JSONDecoder().decode(Mosaic.self, from: Data(bad.utf8)) }
    }

    @Test func findsTheTileUnderAFinger() throws {
        let m = try Self.mosaic(), index = TileIndex(m)
        #expect(index.tile(at: SIMD2(5, 5)) == 0)
        #expect(index.tile(at: SIMD2(15, 2)) == 1)
        #expect(index.tile(at: SIMD2(10, 5)) == nil, "the joint")
        #expect(index.tile(at: SIMD2(10.2, 5), slop: 5) == 1, "a joint near a tile's centre finds it")
        #expect(index.tile(at: SIMD2(-3, 5)) == nil)
        #expect(index.tiles(in: SIMD2(0, 0), SIMD2(5, 5)).contains(0))
        #expect(index.tiles(in: SIMD2(30, 30), SIMD2(40, 40)).isEmpty, "off the canvas")
    }

    @Test func setsOnlyWithTheRightPaint() throws {
        let m = try Self.mosaic()
        var s = Setting()
        let wrong = s.place(0, with: 1, in: m), right = s.place(0, with: 0, in: m), twice = s.place(0, with: 0, in: m)
        #expect(!wrong && right)
        #expect(!twice, "already set")
        #expect(s.remaining(in: m) == [0, 1] && s.fraction(of: m) == 0.5 && !s.isComplete(m))
        #expect(s.nextPaint(after: 0, in: m) == 1)
        s.place(1, with: 1, in: m)
        #expect(s.isComplete(m) && s.nextPaint(after: 1, in: m) == nil)
    }

    @Test func goldIsFoundAndTiltsWhileRedDoesNot() throws {
        let m = try Self.mosaic()
        #expect(TileColor.isGold(m.palette[1]) && !TileColor.isGold(m.palette[0]))
        #expect(TileColor.body(m.palette[0], tile: 3, finish: .flat) == m.palette[0])
        let golds = (0..<50).map { TileColor.body(m.palette[1], tile: $0, finish: .material).x }
        #expect(golds.max()! - golds.min()! > 0.1, "each gold tile catches the light its own way")
        for i in 0..<200 { #expect(abs(TileColor.wobble(i)) <= 1) }
        #expect(TileColor.wobble(7) == TileColor.wobble(7), "deterministic")
    }

    @Test func okLabRoundTrips() {
        for rgb in [SIMD3<Float>(0.8, 0.1, 0.1), SIMD3(0.2, 0.5, 0.9), SIMD3(1, 1, 1), SIMD3(0, 0, 0)] {
            let back = OKLab.toRGB(OKLab.from(rgb))
            #expect(abs(back.x - rgb.x) < 1e-3 && abs(back.y - rgb.y) < 1e-3 && abs(back.z - rgb.z) < 1e-3)
        }
    }
}

@Suite("v0's settings carried over")
struct CarryOverTests {
    @Test func setTilesAreRegionsAndAFinishedWallPaintsItsGrout() {
        #expect(Setting(set: [3, 0, 9, -1]).paintedRegions(tileCount: 5) == [0, 3])
        #expect(Setting(set: [0, 1, 2]).paintedRegions(tileCount: 3) == [0, 1, 2, 3])
        #expect(Setting().paintedRegions(tileCount: 0) == [])
    }

    @Test func v0FileNamesNameTheirWork() {
        #expect(Setting.v0Work(key: "own-1234")! == ("own-1234", nil))
        #expect(Setting.v0Work(key: "young-woman-in-red-standard")! == ("young-woman-in-red", .standard))
        #expect(Setting.v0Work(key: "william-more")! == ("william", .more))
        #expect(Setting.v0Work(key: "-fewer") == nil)
        #expect(Setting.v0Work(key: "notes") == nil)
    }
}
