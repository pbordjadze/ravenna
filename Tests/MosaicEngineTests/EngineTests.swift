import Foundation
import Testing
import MosaicKit
@testable import MosaicEngine

/// The engine end to end on a small synthetic picture: a red disc and a blue stripe on a warm
/// ground, its contour map the shapes' outlines.
@Suite("MosaicEngine")
struct EngineTests {
    static let width = 96, height = 64

    /// With `eye`, a grey-blue iris and a dark pupil painted in the disc where the face's eye is.
    static func picture(eye: Bool = false) -> (MosaicEngine.Photo, [Float]) {
        let w = width, h = height
        var rgb = [SIMD3<Float>](repeating: .zero, count: w * h)
        var contours = [Float](repeating: 0, count: w * h)
        for y in 0..<h {
            for x in 0..<w {
                let d = ((Float(x) - 34) * (Float(x) - 34) + (Float(y) - 30) * (Float(y) - 30)).squareRoot()
                var c = SIMD3<Float>(0.85, 0.75, 0.55) * (0.8 + 0.2 * Float(x) / Float(w))
                if d < 18 { c = SIMD3(0.8, 0.15, 0.1) }
                if y >= 46 && y < 54 { c = SIMD3(0.15, 0.25, 0.75) }
                let e = ((Float(x) - 34) * (Float(x) - 34) + (Float(y) - 28) * (Float(y) - 28)).squareRoot()
                if eye && e < 5 { c = e < 2.2 ? SIMD3(0.05, 0.04, 0.04) : SIMD3(0.45, 0.55, 0.65) }
                rgb[y * w + x] = c
                if abs(d - 18) < 1.2 || (abs(Float(y) - 46) < 1.2 || abs(Float(y) - 53.5) < 1.2) && x > 4 && x < w - 5 {
                    contours[y * w + x] = 1
                }
            }
        }
        return (MosaicEngine.Photo(width: w, height: h, rgb: rgb), contours)
    }

    /// A face over the disc: its box, one eye with a pupil, a dark lid row, a brow, the eye's opening.
    static let face = MosaicEngine.Face(
        box: [14, 10, 56, 48],
        eyes: [[34, 28, 5, 2]],
        lines: [.init(kind: "dark", pts: [[26, 25], [30, 22.5], [36, 22], [42, 25]]),
                .init(kind: "mid", pts: [[24, 17], [34, 15], [44, 17]]),
                .init(kind: "eye", pts: [[26, 25], [30, 22.5], [36, 22], [42, 25], [36, 32], [30, 32], [26, 25]])])

    static func settings() -> MosaicEngine.Settings {
        var s = MosaicEngine.Settings()
        s.paints = 8
        return s
    }

    /// Working pixels (twice the photo) covered by more than one tile, sampling each at its centre.
    static func overlaps(_ m: Mosaic, skip: Set<Int> = []) -> Int {
        let w = width * 4, h = height * 4
        var cover = [UInt8](repeating: 0, count: w * h)
        for (i, t) in m.tiles.enumerated() where !skip.contains(i) {
            let (lo, hi) = t.bounds
            for y in max(Int(lo.y * 4) - 1, 0)...min(Int(hi.y * 4) + 1, h - 1) {
                for x in max(Int(lo.x * 4) - 1, 0)...min(Int(hi.x * 4) + 1, w - 1) {
                    if t.contains(SIMD2((Float(x) + 0.5) / 4, (Float(y) + 0.5) / 4)) { cover[y * w + x] += 1 }
                }
            }
        }
        return cover.filter { $0 > 1 }.count
    }

    /// The stages in build order: eyes and features, strands, rows, the field; then the pupils.
    static func inBuildOrder(_ stages: [Mosaic.Stage]) -> Bool {
        func rank(_ s: Mosaic.Stage) -> Int {
            switch s { case .eye, .feature: 0; case .strand: 1; case .row: 2; case .field: 3 }
        }
        var body = stages
        while body.last == .eye { body.removeLast() }
        return zip(body, body.dropFirst()).allSatisfy { rank($0) <= rank($1) }
    }

    @Test func makesADeterministicMosaicOfSeparateTiles() throws {
        let (photo, contours) = Self.picture()
        let a = try MosaicEngine.make(photo: photo, contours: contours, faces: [], settings: Self.settings())
        let b = try MosaicEngine.make(photo: photo, contours: contours, faces: [], settings: Self.settings())
        #expect(a == b, "the same picture makes the same mosaic")
        #expect(a.width == 96 && a.height == 64)
        #expect(a.tiles.count >= 20 && a.tiles.count <= 160, "\(a.tiles.count) tiles")
        #expect(!a.palette.isEmpty && a.palette.count <= 8)
        for t in a.tiles {
            #expect(t.corners.count >= 3)
            #expect(a.palette.indices.contains(t.paint))
            #expect(!t.stone, "no face, no stone")
            let (lo, hi) = t.bounds
            #expect(lo.x >= 0 && lo.y >= 0 && hi.x <= 96 && hi.y <= 64)
        }
        #expect(a.palette.allSatisfy { $0.min() >= 0 && $0.max() <= 1 })
        #expect(Self.overlaps(a) == 0, "tiles never overlap")
        // The disc's tiles are red, the stripe's blue.
        let disc = a.tiles.filter { distance($0.centre, SIMD2(34, 30)) < 10 }
        #expect(!disc.isEmpty && disc.allSatisfy { a.palette[$0.paint].x > a.palette[$0.paint].z })
        let stripe = a.tiles.filter { $0.centre.y > 47.5 && $0.centre.y < 52 && $0.centre.x > 10 && $0.centre.x < 86 }
        #expect(!stripe.isEmpty && stripe.allSatisfy { a.palette[$0.paint].z > a.palette[$0.paint].x })
    }

    @Test func recordsEachTilesStageInBuildOrder() throws {
        let (photo, contours) = Self.picture()
        var trace = MosaicEngine.Trace()
        let m = try MosaicEngine.make(photo: photo, contours: contours, faces: [], settings: Self.settings(),
                                      cancel: { false }, trace: &trace)
        let stages = m.tiles.compactMap(\.stage)
        #expect(stages.count == m.tiles.count, "every tile has its stage")
        #expect(Self.inBuildOrder(stages))
        #expect(stages.contains(.strand) && stages.contains(.row), "the outlines are laid and echoed")
        #expect(trace.strand.count == m.tiles.count && trace.feature.count == m.tiles.count)
        #expect(trace.stages.map(\.name) == ["upscale", "strokes", "strands", "segments", "distance", "rows", "gaps", "colours", "palette"])
        #expect(trace.stages.last?.tiles == m.tiles.count)
        for (t, strand) in zip(m.tiles, trace.strand) { #expect(strand == (t.stage == .strand)) }
    }

    @Test func setsAFacesFeaturesFirstAndItsPupilLast() throws {
        let (photo, contours) = Self.picture(eye: true)
        var trace = MosaicEngine.Trace()
        let m = try MosaicEngine.make(photo: photo, contours: contours, faces: [Self.face], settings: Self.settings(),
                                      cancel: { false }, trace: &trace)
        let stages = m.tiles.compactMap(\.stage)
        #expect(stages.count == m.tiles.count && Self.inBuildOrder(stages))
        #expect(stages.first == .eye, "the iris first")
        #expect(stages.last == .eye, "the pupil last, over its iris")
        #expect(stages.filter { $0 == .eye }.count == 2)
        #expect(stages.contains(.feature))
        #expect(trace.feature.contains("dark") && trace.feature.contains("mid"))
        #expect(m.tiles.contains { $0.stone } && m.tiles.contains { !$0.stone })
        for t in m.tiles where t.stone {
            #expect(t.centre.x >= 14 && t.centre.x <= 56 && t.centre.y >= 10 && t.centre.y <= 48)
        }
        // The pupil is darker than its iris and inside the eye's opening; only it overlaps anything.
        let iris = m.tiles[0], pupil = m.tiles[m.tiles.count - 1]
        func luma(_ c: SIMD3<Float>) -> Float { 0.2126 * c.x + 0.7152 * c.y + 0.0722 * c.z }
        #expect(luma(m.palette[pupil.paint]) <= luma(m.palette[iris.paint]))
        #expect(distance(pupil.centre, SIMD2(34, 28)) < 2)
        #expect(Self.overlaps(m, skip: [m.tiles.count - 1]) == 0)
        // The face's tiles are finer than the rest.
        func area(_ t: Mosaic.Tile) -> Float { Float(MosaicEngine.Polygon.area(t.corners.map { SIMD2(Double($0.x), Double($0.y)) })) }
        let face = m.tiles.filter { $0.stone && $0.stage == .row }.map(area), rest = m.tiles.filter { !$0.stone && $0.stage == .row }.map(area)
        if !face.isEmpty && !rest.isEmpty { #expect(face.max()! <= rest.max()!) }
        let again = try MosaicEngine.make(photo: photo, contours: contours, faces: [Self.face], settings: Self.settings())
        #expect(again == m)
    }

    @Test func colorsAnIrisAsItLooksOrAsInThePhoto() throws {
        let (photo, contours) = Self.picture(eye: true)
        let painted = SIMD3<Float>(0.45, 0.55, 0.65)
        func iris(_ eyes: MosaicEngine.Eyes) throws -> SIMD3<Float> {
            var s = Self.settings()
            s.eyes = eyes
            let m = try MosaicEngine.make(photo: photo, contours: contours, faces: [Self.face], settings: s)
            return m.palette[m.tiles[0].paint]
        }
        func off(_ c: SIMD3<Float>) -> Float { ((c - painted) * (c - painted)).sum().squareRoot() }
        let looks = try iris(.asTheyLook), photo_ = try iris(.asInThePhoto)
        #expect(off(photo_) < 0.02, "the photo's own grey-blue: \(photo_)")
        #expect(off(looks) > off(photo_), "as it looks, stronger than the photo's")
    }

    @Test func readsTheFeaturesJSON() throws {
        let json = #"{"box": [97, 263, 603, 802], "eyes": [[303.9, 442.2, 17.5, 7.0]], "lines": [{"kind": "dark", "pts": [[273.5, 436.3], [278.5, 434.3]]}]}"#
        let f = try JSONDecoder().decode(MosaicEngine.Face.self, from: Data(json.utf8))
        #expect(f.box == [97, 263, 603, 802] && f.eyes == [[303.9, 442.2, 17.5, 7.0]])
        #expect(f.lines == [.init(kind: "dark", pts: [[273.5, 436.3], [278.5, 434.3]])])
        let bare = try JSONDecoder().decode(MosaicEngine.Face.self, from: Data(#"{"box": [1, 2, 3, 4]}"#.utf8))
        #expect(bare.eyes.isEmpty && bare.lines.isEmpty)
    }

    @Test func stopsWhenCancelledAndRefusesBadInput() throws {
        let (photo, contours) = Self.picture()
        var polls = 0
        #expect(throws: CancellationError.self) {
            try MosaicEngine.make(photo: photo, contours: contours, faces: [], cancel: { polls += 1; return polls >= 2 })
        }
        #expect(polls == 2, "polled between stages, stopping at the first that says so")
        #expect(throws: MosaicEngine.InputError.contourSize) {
            try MosaicEngine.make(photo: photo, contours: [0, 1], faces: [])
        }
        #expect(throws: MosaicEngine.InputError.photoSize) {
            try MosaicEngine.make(photo: .init(width: 3, height: 3, rgb: []), contours: [], faces: [])
        }
        // A picture smaller than a tile makes a mosaic without tiles rather than failing.
        let tiny = try MosaicEngine.make(photo: .init(width: 4, height: 3, rgb: .init(repeating: SIMD3(0.5, 0.5, 0.5), count: 12)),
                                         contours: .init(repeating: 0, count: 12), faces: [])
        #expect(tiny.width == 4 && tiny.tiles.allSatisfy { tiny.palette.indices.contains($0.paint) })
    }

    @Test func paintsTheBedUnderTheTiles() throws {
        let (photo, contours) = Self.picture()
        let m = try MosaicEngine.make(photo: photo, contours: contours, faces: [], settings: Self.settings())
        let bed = MosaicEngine.bed(of: m, width: 96, height: 64)
        #expect(bed.count == 96 * 64)
        #expect(bed.allSatisfy { $0.min() >= 0 && $0.max() <= 1 })
        // Under the disc it's a darker, greyer red; under the stripe a darker blue.
        let red = bed[30 * 96 + 34], blue = bed[50 * 96 + 60]
        #expect(red.x > red.z && blue.z > blue.x)
        let disc = m.palette[m.tiles.min { distance($0.centre, SIMD2(34, 30)) < distance($1.centre, SIMD2(34, 30)) }!.paint]
        #expect(red.x < disc.x, "darker than the tiles")
        #expect(MosaicEngine.bed(of: m, width: 48, height: 32).count == 48 * 32)
        let empty = Mosaic(width: 10, height: 10, grout: SIMD3(0.8, 0.8, 0.8), palette: [], tiles: [])
        #expect(MosaicEngine.bed(of: empty, width: 5, height: 5) == .init(repeating: SIMD3(0.8, 0.8, 0.8), count: 25))
    }
}

@inline(__always) private func distance(_ a: SIMD2<Float>, _ b: SIMD2<Float>) -> Float {
    let d = a - b
    return (d * d).sum().squareRoot()
}
