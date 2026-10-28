import Foundation
import Testing
import MosaicKit
@testable import MosaicEngine

/// What the painter draws in Refine (`MosaicEngine.Mark`), kept in the recipe.
@Suite("Refine's marks")
struct MarksTests {
    typealias Recipe = MosaicEngine.Recipe
    typealias Mark = MosaicEngine.Mark

    /// A 10 by 10 grid of 10-unit square tiles, the top three rows one blue (the background the
    /// gold ground finds), the rest a red figure.
    static func grid() -> Mosaic {
        var tiles: [Mosaic.Tile] = []
        for r in 0..<10 { for c in 0..<10 {
            let x = Float(c * 10), y = Float(r * 10)
            tiles.append(.init(corners: [SIMD2(x + 0.5, y + 0.5), SIMD2(x + 9.5, y + 0.5), SIMD2(x + 9.5, y + 9.5), SIMD2(x + 0.5, y + 9.5)],
                               paint: r < 3 ? 0 : 1))
        } }
        return Mosaic(width: 100, height: 100, grout: SIMD3(0.8, 0.8, 0.8),
                      palette: [SIMD3(0.2, 0.3, 0.7), SIMD3(0.7, 0.2, 0.15)], tiles: tiles)
    }

    @Test func marksRoundTripRoundedAndOnlyWhenThere() throws {
        let line = Mark(kind: .line, width: 0.004, points: [SIMD2(0.123456, 0.5), SIMD2(0.9, 0.654321)])
        let recipe = Recipe(ground: .gold, marks: [line, Mark(kind: .ungold, width: 0.05, points: [SIMD2(0.5, 0.5)])])
        let read = try JSONDecoder().decode(Recipe.self, from: JSONEncoder().encode(recipe))
        #expect(read.marks.count == 2 && read.marks[1].kind == .ungold)
        #expect(read.marks[0].points == [SIMD2(0.1235, 0.5), SIMD2(0.9, 0.6543)])
        // A recipe never refined is written as it always was.
        let plain = String(decoding: try JSONEncoder().encode(Recipe()), as: UTF8.self)
        #expect(!plain.contains("marks"))
    }

    @Test func aMarkThatDoesNotReadIsPassedOverAlone() throws {
        let json = #"""
        {"marks": [{"kind": "line", "width": 0.004, "points": [0.1, 0.2, 0.3, 0.4]},
                   {"kind": "sparkle", "width": 0.1, "points": [0.5, 0.5]},
                   {"kind": "gold", "width": -1, "points": [0.5, 0.5]},
                   {"kind": "gold", "width": 0.1, "points": [0.5]},
                   {"kind": "gold", "width": 9, "points": [0.5, 0.5]},
                   "nonsense"]}
        """#
        let read = try JSONDecoder().decode(Recipe.self, from: Data(json.utf8))
        #expect(read.marks.map(\.kind) == [.line, .gold])
        #expect(read.marks[1].width == Mark.maximumWidth)
        #expect(try JSONDecoder().decode(Recipe.self, from: Data(#"{"marks": 3}"#.utf8)).marks.isEmpty)
    }

    @Test func onlyLinesChangeTheTiles() {
        let line = Mark(kind: .line, width: 0.004, points: [SIMD2(0, 0), SIMD2(1, 1)])
        let gold = Mark(kind: .gold, width: 0.1, points: [SIMD2(0.5, 0.5)])
        let standard = Recipe.detailPieces[.standard]!
        #expect(Recipe(pieces: standard, marks: [gold]).bundledDetail == .standard)
        #expect(Recipe(pieces: standard, marks: [gold, line]).bundledDetail == nil)
        let tiles = Recipe(ground: .gold, marks: [gold, line]).forTiles
        #expect(tiles == Recipe(marks: [line]))
        #expect(Recipe(ground: .gold, marks: [gold]).forTiles == Recipe())
    }

    @Test func goldIsBrushedOnAndOffInTheOrderDrawn() {
        let m = Self.grid()
        // A dab in the figure's middle lays the four tiles round it in gold.
        let dab = Mark(kind: .gold, width: 0.15, points: [SIMD2(0.5, 0.5)])
        #expect(dab.tiles(of: m) == [44, 45, 54, 55])
        let brushed = Recipe(marks: [dab]).laid(m)
        #expect(brushed.palette.last == Mosaic.groundGold)
        #expect([44, 45, 54, 55].allSatisfy { TileColor.isGold(brushed.palette[brushed.tiles[$0].paint]) })
        #expect(brushed.tiles[43].paint == m.tiles[43].paint)
        // The gold ground with its top row's middle taken off, then one tile put back.
        let off = Mark(kind: .ungold, width: 0.1, points: [SIMD2(0.3, 0.05), SIMD2(0.7, 0.05)])
        let back = Mark(kind: .gold, width: 0.02, points: [SIMD2(0.55, 0.05)])
        let r = Recipe(ground: .gold, marks: [off, back])
        let gold = Set(r.goldTiles(of: m))
        #expect(gold == Set(m.background()).subtracting([2, 3, 4, 6, 7]))
        #expect(!gold.contains(4) && gold.contains(5) && gold.contains(25))
        // Without gold marks, laying is as it was.
        #expect(Recipe(ground: .gold, marks: [Mark(kind: .line, width: 0.004, points: [SIMD2(0, 0)])]).laid(m) == m.goldGround())
    }

    @Test func linesAreDrawnIntoTheContoursAndRubbedOut() {
        let w = 200, h = 100
        var contours = [Float](repeating: 0.3, count: w * h)
        let r = Recipe(marks: [
            Mark(kind: .line, width: 0.01, points: [SIMD2(0.1, 0.5), SIMD2(0.9, 0.5)]),
            Mark(kind: .unline, width: 0.1, points: [SIMD2(0.5, 0.5)]),
            Mark(kind: .gold, width: 0.5, points: [SIMD2(0.2, 0.2)]),
        ])
        r.mark(contours: &contours, width: w, height: h)
        // Along the line it is an outline (above the engine's cut); off it, as it was.
        #expect(contours[50 * w + 40] > 0.85 && contours[50 * w + 160] > 0.85)
        #expect(contours[49 * w + 40] > MosaicEngine.Settings().cut)
        #expect(contours[20 * w + 40] == 0.3, "the gold mark leaves the contours alone")
        // Under the rub-out, nothing, the line too; beyond it, back.
        #expect(contours[50 * w + 100] == 0 && contours[45 * w + 100] == 0)
        #expect(contours[50 * w + 100 + 18] > 0.85)
        #expect(contours[20 * w + 100] == 0.3)
    }

    @Test func aThinLineStaysAPixelWideOnADraft() {
        var contours = [Float](repeating: 0, count: 60 * 60)
        Recipe(marks: [Mark(kind: .line, width: 0.001, points: [SIMD2(0, 0.5), SIMD2(1, 0.5)])])
            .mark(contours: &contours, width: 60, height: 60)
        #expect((0..<60).allSatisfy { contours[30 * 60 + $0] > 0.72 || contours[29 * 60 + $0] > 0.72 })
    }

    @Test func marksStayOnThePhotoWhenThePanelMoves() {
        // A dab at the middle of a square panel at the right of a 400 by 300 photo.
        let square = Recipe(panel: .square, centre: SIMD2(1, 0.5), marks: [Mark(kind: .gold, width: 0.1, points: [SIMD2(0.5, 0.5)])])
        var whole = square
        whole.panel = .whole
        let moved = whole.reframingMarks(from: square, photoWidth: 400, photoHeight: 300)
        // The square is x 0.25...1 of the photo: its middle is the photo's 0.625; its long side,
        // 300, is three quarters of the photo's.
        #expect(abs(moved.marks[0].points[0].x - 0.625) < 1e-12 && abs(moved.marks[0].points[0].y - 0.5) < 1e-12)
        #expect(abs(moved.marks[0].width - 0.075) < 1e-12)
        var squareAgain = moved
        squareAgain.panel = .square
        squareAgain.centre = SIMD2(1, 0.5)
        let back = squareAgain.reframingMarks(from: moved, photoWidth: 400, photoHeight: 300)
        #expect(abs(back.marks[0].points[0].x - 0.5) < 1e-12 && abs(back.marks[0].width - 0.1) < 1e-12)
        #expect(whole.reframingMarks(from: whole, photoWidth: 400, photoHeight: 300) == whole)
    }
}
