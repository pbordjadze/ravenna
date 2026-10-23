import Testing
@testable import MosaicKit

/// A 10 by 10 grid of square tiles: a figure (paint 1, its face stone) in the middle on a
/// background (paint 0), a floor along the bottom (paint 2), and one tile of the background's paint
/// inside the figure.
@Suite("The gold ground")
struct GroundTests {
    static func figure(island: Bool = true) -> Mosaic {
        var tiles: [Mosaic.Tile] = []
        for r in 0..<10 { for c in 0..<10 {
            let x = Float(c * 10), y = Float(r * 10)
            var paint = 0, stone = false
            if r == 9 { paint = 2 }
            if (3...8).contains(c), (3...8).contains(r) { paint = 1 }
            if (5...6).contains(c), (4...5).contains(r) { stone = true }
            if island, c == 5, r == 7 { paint = 0 }
            tiles.append(.init(corners: [SIMD2(x + 0.5, y + 0.5), SIMD2(x + 9.5, y + 0.5), SIMD2(x + 9.5, y + 9.5), SIMD2(x + 0.5, y + 9.5)],
                               paint: paint, stone: stone))
        } }
        return Mosaic(width: 100, height: 100, grout: SIMD3(0.8, 0.8, 0.8),
                      palette: [SIMD3(0.3, 0.35, 0.5), SIMD3(0.6, 0.3, 0.2), SIMD3(0.4, 0.3, 0.2)], tiles: tiles)
    }

    @Test func theBackgroundIsFoundFromTheTop() {
        let m = Self.figure(), back = Set(m.background())
        #expect(TileColor.isGold(Mosaic.groundGold))
        #expect(back.contains(0) && back.contains(9), "the top corners")
        #expect(back.allSatisfy { m.tiles[$0].paint == 0 })
        #expect(!back.contains(7 * 10 + 5), "the island inside the figure isn't reached")
        #expect(back.count == m.tiles.filter { $0.paint == 0 }.count - 1)
    }

    @Test func theGroundTurnsGoldAndTheSettingCarriesOver() {
        let m = Self.figure(), g = m.goldGround()
        #expect(g.tiles.count == m.tiles.count && g.palette.count == 4)
        #expect(g.palette.last == Mosaic.groundGold && g.tiles[0].paint == 3)
        #expect(g.tiles[7 * 10 + 5].paint == 0, "the island keeps its paint")
        #expect(g.tiles[45].paint == 1 && g.tiles[95].paint == 2, "the figure and the floor are left alone")

        // Without the island, the background's paint is left with no tiles and is dropped.
        let bare = Self.figure(island: false).goldGround()
        #expect(bare.palette.count == 3 && bare.palette.last == Mosaic.groundGold)
        #expect(bare.tiles[45].paint == 0 && bare.tiles[95].paint == 1 && bare.tiles[0].paint == 2)
        #expect(Set(bare.tiles.map(\.paint)) == [0, 1, 2])

        var s = Setting()
        s.place(0, with: 3, in: g)
        #expect(s.remaining(in: g)[3] == g.tiles.filter { $0.paint == 3 }.count - 1)
    }

    @Test func aMosaicWithNoGroundIsLeftAlone() {
        let m = Mosaic(width: 10, height: 10, grout: SIMD3(0.8, 0.8, 0.8), palette: [Mosaic.groundGold],
                       tiles: [.init(corners: [SIMD2(0, 0), SIMD2(10, 0), SIMD2(10, 10), SIMD2(0, 10)], paint: 0)])
        #expect(m.background().isEmpty, "already gold")
        #expect(m.goldGround() == m)
    }
}
