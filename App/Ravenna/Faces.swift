import CoreGraphics
import Foundation
import Vision

/// The faces in a photo, as the engine sets them (`MosaicEngine.Face`): each feature as its own
/// pieces, from Vision's face landmarks, mapped as the sketchbook's bench maps MediaPipe's
/// (`sketchbook/features.py`): upper lids and the line where the lips meet as dark rows; brows and
/// the nose's shadow side as rows in their own shadow; lower lids and the lips' outline as rows in
/// their tone; the eye openings and the lips as areas. Cats' and dogs' faces get a box (finer
/// tiles) and no features.
nonisolated enum Faces {
    /// `image` is the photo at its working size, so the points come out in its pixels; `rgba` is
    /// the same pixels (sRGB, 4 bytes each), for telling which side of the nose is in shadow.
    static func find(in image: CGImage, rgba: [UInt8]) throws -> [MosaicEngine.Face] {
        let w = CGFloat(image.width), h = CGFloat(image.height)
        let faces = VNDetectFaceLandmarksRequest()
        let animals = VNRecognizeAnimalsRequest()
        try VNImageRequestHandler(cgImage: image, orientation: .up).perform([faces, animals])
        var found: [MosaicEngine.Face] = []
        // Vision's points have their origin at the bottom left.
        func pts(_ r: VNFaceLandmarkRegion2D?) -> [SIMD2<Float>] {
            (r?.pointsInImage(imageSize: CGSize(width: w, height: h)) ?? []).map { SIMD2(Float($0.x), Float(h - $0.y)) }
        }
        func box(_ b: CGRect, margin: CGFloat) -> [Float] {
            let x0 = b.minX * w, x1 = b.maxX * w, y0 = (1 - b.maxY) * h, y1 = (1 - b.minY) * h, m = margin * (x1 - x0)
            return [Float(max(0, x0 - m)), Float(max(0, y0 - m)), Float(min(w, x1 + m)), Float(min(h, y1 + m))]
        }
        func lum(_ p: SIMD2<Float>) -> Float {
            let x = min(max(Int(p.x), 0), image.width - 1), y = min(max(Int(p.y), 0), image.height - 1)
            let i = (y * image.width + x) * 4
            return 0.2126 * Float(rgba[i]) + 0.7152 * Float(rgba[i + 1]) + 0.0722 * Float(rgba[i + 2])
        }
        for face in faces.results ?? [] {
            guard let l = face.landmarks else { continue }
            var lines: [MosaicEngine.Face.Line] = []
            func add(_ kind: String, _ p: [SIMD2<Float>]) {
                if p.count >= 2 { lines.append(.init(kind: kind, pts: p.map { [$0.x, $0.y] })) }
            }
            var eyes: [[Float]] = []
            for (eye, pupil) in [(pts(l.leftEye), pts(l.leftPupil)), (pts(l.rightEye), pts(l.rightPupil))] where eye.count >= 4 {
                let (upper, lower) = halves(eye)
                add("dark", upper); add("tone", lower)
                add("eye", eye)
                let xs = eye.map(\.x), width = (xs.max() ?? 0) - (xs.min() ?? 0)
                let centre = pupil.first ?? eye.reduce(.zero, +) / Float(eye.count)
                let r = 0.21 * width
                eyes.append([centre.x, centre.y, r, 0.4 * r])
            }
            for brow in [pts(l.leftEyebrow), pts(l.rightEyebrow)] { add("mid", midline(brow)) }
            // The nose: down its side in shadow, from the top of its crest to the wing.
            let nose = pts(l.nose), crest = pts(l.noseCrest)
            if nose.count >= 4, let top = crest.min(by: { $0.y < $1.y }) {
                let cx = nose.map(\.x).reduce(0, +) / Float(nose.count)
                let left = nose.filter { $0.x < cx }.sorted { $0.y < $1.y }
                let right = nose.filter { $0.x >= cx }.sorted { $0.y < $1.y }
                let mean = { (p: [SIMD2<Float>]) in p.isEmpty ? Float.infinity : p.map(lum).reduce(0, +) / Float(p.count) }
                add("mid", [top] + (mean(left) <= mean(right) ? left : right))
            }
            let outer = pts(l.outerLips), inner = pts(l.innerLips)
            if outer.count >= 4 {
                let (upper, lower) = halves(outer)
                add("tone", upper); add("tone", lower)
                add("lips", outer)
            }
            if inner.count >= 4 { add("dark", halves(inner).upper) }
            found.append(.init(box: box(face.boundingBox, margin: 0.12), eyes: eyes, lines: lines))
        }
        for animal in animals.results ?? [] {
            found.append(.init(box: box(animal.boundingBox, margin: 0.05), eyes: [], lines: []))
        }
        return found
    }

    /// A brow's row: between its upper and lower edges when Vision outlines it as a ring (as the
    /// bench takes MediaPipe's), else its points left to right.
    static func midline(_ brow: [SIMD2<Float>]) -> [SIMD2<Float>] {
        // A ring closes with a step like its others; an open line ends across the brow from its start.
        func gap(_ a: SIMD2<Float>, _ b: SIMD2<Float>) -> Float { ((b - a) * (b - a)).sum().squareRoot() }
        let longest = zip(brow, brow.dropFirst()).map(gap).max() ?? 0
        guard brow.count >= 6, let first = brow.first, let last = brow.last, gap(last, first) <= 1.5 * longest else {
            return brow.sorted { $0.x < $1.x }
        }
        let (upper, lower) = halves(brow)
        guard upper.count >= 3, lower.count >= 3 else { return brow.sorted { $0.x < $1.x } }
        let n = max(upper.count, lower.count)
        return (0..<n).map { k in (along(upper, Float(k) / Float(n - 1)) + along(lower, Float(k) / Float(n - 1))) / 2 }
    }

    /// The point a fraction `t` of the way along a polyline, by length.
    static func along(_ p: [SIMD2<Float>], _ t: Float) -> SIMD2<Float> {
        let seg = zip(p, p.dropFirst()).map { (($1 - $0) * ($1 - $0)).sum().squareRoot() }
        var left = t * seg.reduce(0, +)
        for (i, d) in seg.enumerated() {
            if left <= d || i == seg.count - 1 { return p[i] + (p[i + 1] - p[i]) * (d > 0 ? min(left / d, 1) : 0) }
            left -= d
        }
        return p[0]
    }

    /// A closed outline's upper and lower halves, each from its leftmost point to its rightmost (y down).
    static func halves(_ ring: [SIMD2<Float>]) -> (upper: [SIMD2<Float>], lower: [SIMD2<Float>]) {
        guard let a = ring.indices.min(by: { ring[$0].x < ring[$1].x }),
              let b = ring.indices.max(by: { ring[$0].x < ring[$1].x }), a != b else { return (ring, []) }
        let n = ring.count
        var one: [SIMD2<Float>] = [], two: [SIMD2<Float>] = []
        var i = a
        while true { one.append(ring[i]); if i == b { break }; i = (i + 1) % n }
        i = a
        while true { two.append(ring[i]); if i == b { break }; i = (i - 1 + n) % n }
        let mean = { (p: [SIMD2<Float>]) in p.map(\.y).reduce(0, +) / Float(max(p.count, 1)) }
        return mean(one) <= mean(two) ? (one, two) : (two, one)
    }
}
