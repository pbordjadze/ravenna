import Foundation
import Testing
import MosaicKit
@testable import MosaicEngine

/// What a mosaic is made with, as the app records it (`meta.json`'s `recipe`).
@Suite("Recipe")
struct RecipeTests {
    typealias Recipe = MosaicEngine.Recipe

    @Test func piecesRunFromHalfToThreeTimesTheStandardCount() {
        #expect(Recipe.longSide(pieces: 0) == 724)
        #expect(Recipe.longSide(pieces: Recipe.standardPieces) == 1024)
        #expect(Recipe.longSide(pieces: Recipe.detailPieces[.more]!) == 1448)
        #expect(Recipe.longSide(pieces: 1) == 1774)
        #expect(Recipe.longSide(pieces: -3) == 724 && Recipe.longSide(pieces: 9) == 1774)
        #expect(abs(Recipe.multiple(pieces: Recipe.standardPieces) - 1) < 1e-12)
        #expect(abs(Recipe.multiple(pieces: 1) - 3) < 1e-12)
    }

    @Test func bundledDetailOnlyForTheBundledChoices() {
        #expect(Recipe().bundledDetail == .standard)
        #expect(Recipe(pieces: 0).bundledDetail == .fewer)
        #expect(Recipe(pieces: Recipe.detailPieces[.more]!, finish: .flat, ground: .gold).bundledDetail == .more)
        #expect(Recipe(pieces: 0.5).bundledDetail == nil)
        #expect(Recipe(eyes: .asInThePhoto).bundledDetail == nil)
        #expect(Recipe(mouth: .byzantine).bundledDetail == nil)
        #expect(Recipe(panel: .square).bundledDetail == nil)
    }

    @Test func smallerSidesLayFinerTiles() {
        let recipe = Recipe(eyes: .asInThePhoto, mouth: .byzantine)
        let full = recipe.settings(side: 1024)
        #expect(full == {
            var s = MosaicEngine.Settings(); s.eyes = .asInThePhoto; s.mouth = .byzantine; return s
        }())
        let half = recipe.settings(side: 512)
        #expect(half.pitch == full.pitch / 2 && half.facePitch == full.facePitch / 2 && half.grout == 1)
        #expect(half.eyes == .asInThePhoto && half.mouth == .byzantine && half.paints == full.paints)
        #expect(recipe.settings(side: 2048) == full)
    }

    @Test func roundTripsAndToleratesWhatItDoesNotKnow() throws {
        let recipe = Recipe(pieces: 0.8, eyes: .asInThePhoto, mouth: .byzantine, finish: .bed, ground: .gold,
                            panel: .upright, centre: SIMD2(0.25, 0.75))
        let data = try JSONEncoder().encode(recipe)
        #expect(try JSONDecoder().decode(Recipe.self, from: data) == recipe)
        let odd = #"{"pieces": 7, "eyes": "glowing", "finish": "bed", "panel": "round", "centre": [0.1], "future": 1}"#
        let read = try JSONDecoder().decode(Recipe.self, from: Data(odd.utf8))
        #expect(read == Recipe(pieces: 1, finish: .bed))
        #expect(try JSONDecoder().decode(Recipe.self, from: Data("{}".utf8)) == Recipe())
    }

    @Test func panelsFitThePhotoAndStayOnIt() {
        let whole = MosaicEngine.Panel.whole.rect(width: 400, height: 300, centre: SIMD2(0.9, 0.9))
        #expect(whole == (0, 0, 1, 1))
        let square = MosaicEngine.Panel.square.rect(width: 400, height: 300, centre: SIMD2(0.95, 0.5))
        #expect(abs(square.width - 0.75) < 1e-12 && square.height == 1 && abs(square.x - 0.25) < 1e-12 && square.y == 0)
        let wide = MosaicEngine.Panel.wide.rect(width: 300, height: 400, centre: SIMD2(0.5, 0))
        #expect(wide.width == 1 && abs(wide.height - 0.5) < 1e-12 && wide.y == 0)
    }

    @Test func facesScaleWithThePhoto() {
        let face = MosaicEngine.Face(box: [10, 20, 30, 40], eyes: [[5, 6, 2, 1]], lines: [.init(kind: "dark", pts: [[1, 2], [3, 4]])])
        let scaled = face.scaled(by: 2)
        #expect(scaled.box == [20, 40, 60, 80] && scaled.eyes == [[10, 12, 4, 2]] && scaled.lines[0].pts == [[2, 4], [6, 8]])
        #expect(scaled.lines[0].kind == "dark")
    }

    @Test func goldGroundIsLaidOn() {
        let m = Mosaic(width: 10, height: 10, grout: SIMD3(1, 1, 1), palette: [SIMD3(0.2, 0.3, 0.8)],
                       tiles: [.init(corners: [SIMD2(0, 0), SIMD2(4, 0), SIMD2(4, 4)], paint: 0)])
        #expect(Recipe().laid(m) == m)
        #expect(Recipe(ground: .gold).laid(m) == m.goldGround())
    }
}
