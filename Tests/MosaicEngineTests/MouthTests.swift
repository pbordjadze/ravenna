import Testing
import MosaicKit
@testable import MosaicEngine

/// The Byzantine mouth (`MosaicEngine.Mouth.byzantine`): a smile with its teeth redrawn small and
/// closed, the rest of the face untouched.
@Suite("Mouth")
struct MouthTests {
    static let width = 120, height = 100

    /// Skin, with a wide open smile: red lips round a band of white teeth, x 30...90, y 50...70.
    static func smile() -> (MosaicEngine.Photo, [Float], MosaicEngine.Face) {
        let w = width, h = height
        var rgb = [SIMD3<Float>](repeating: SIMD3(0.85, 0.68, 0.58), count: w * h)
        var contours = [Float](repeating: 0, count: w * h)
        for y in 50...70 {
            for x in 30...90 {
                let s = (Float(x) - 60) / 30, edge = 10 * (1 - s * s)
                guard abs(Float(y) - 60) <= edge else { continue }
                rgb[y * w + x] = abs(Float(y) - 60) < 0.5 * edge ? SIMD3(0.95, 0.95, 0.92) : SIMD3(0.75, 0.15, 0.15)
                if abs(abs(Float(y) - 60) - edge) < 1 { contours[y * w + x] = 1 }
            }
        }
        let upper: [[Float]] = stride(from: 30, through: 90, by: 10).map { x in let s = (Float(x) - 60) / 30; return [Float(x), 60 - 10 * (1 - s * s)] }
        let lower: [[Float]] = upper.map { [$0[0], 120 - $0[1]] }
        let face = MosaicEngine.Face(box: [10, 10, 110, 95], eyes: [[45, 30, 5, 2]], lines: [
            .init(kind: "dark", pts: [[38, 28], [45, 25], [52, 28]]),
            .init(kind: "tone", pts: upper), .init(kind: "tone", pts: lower),
            .init(kind: "lips", pts: upper + Array(lower.reversed().dropFirst().dropLast())),
            .init(kind: "dark", pts: upper.map { [$0[0], 60 - 0.5 * (60 - $0[1])] }),
        ])
        return (MosaicEngine.Photo(width: w, height: h, rgb: rgb), contours, face)
    }

    @Test func redrawsASmileSmallAndClosed() {
        var (photo, contours, face) = Self.smile()
        let before = photo
        var faces = [face]
        MosaicEngine.byzantineMouths(&photo, &contours, &faces)
        let lines = faces[0].lines
        // The eye's lid is kept, first; the mouth's four lines follow, the new mouth's.
        #expect(lines.map(\.kind) == ["dark", "tone", "tone", "lips", "dark"])
        #expect(lines[0] == Self.smile().2.lines[0])
        let xs = lines[3].pts.map { $0[0] }
        #expect(abs((xs.max()! - xs.min()!) - 48) < 0.01, "0.8 of the smile's 60 px")
        // No teeth left, the skin round the mouth as it was, and no contours under the old mouth.
        let teeth = photo.rgb.filter { $0.x > 0.9 && $0.y > 0.9 }.count
        #expect(teeth == 0)
        #expect(photo.rgb[5 * Self.width + 5] == before.rgb[5 * Self.width + 5])
        #expect(contours.allSatisfy { $0 == 0 })
        // The lips: red, the upper deeper than the lower.
        let at = { (x: Int, y: Int) in photo.rgb[y * Self.width + x] }
        let top = lines[1].pts[5], bottom = lines[2].pts[5], meet = lines[4].pts[5]
        let upperLip = at(60, Int(meet[1] + 0.3 * (top[1] - meet[1]))), lowerLip = at(60, Int((bottom[1] + meet[1]) / 2))
        #expect(upperLip.x > 2 * upperLip.y && lowerLip.x > 2 * lowerLip.y)
        #expect(lowerLip.x > upperLip.x)
    }

    @Test func leavesAFaceWithoutLipsAsItIs() {
        var (photo, contours, _) = Self.smile()
        let cat = MosaicEngine.Face(box: [10, 10, 110, 95], eyes: [[45, 30, 5, 2]])
        var faces = [cat]
        MosaicEngine.byzantineMouths(&photo, &contours, &faces)
        #expect(faces == [cat] && photo.rgb == Self.smile().0.rgb)
    }

    @Test func makesTheSameMosaicTwice() throws {
        let (photo, contours, face) = Self.smile()
        var s = MosaicEngine.Settings()
        s.paints = 8; s.mouth = .byzantine
        let a = try MosaicEngine.make(photo: photo, contours: contours, faces: [face], settings: s)
        let b = try MosaicEngine.make(photo: photo, contours: contours, faces: [face], settings: s)
        s.mouth = .asInThePhoto
        let c = try MosaicEngine.make(photo: photo, contours: contours, faces: [face], settings: s)
        #expect(a == b && a != c)
    }
}
