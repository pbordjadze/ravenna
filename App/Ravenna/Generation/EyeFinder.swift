import CoreGraphics
import Foundation
import os
import simd
import Vision

/// People's eyes, which a coloring book outlines whatever their contrast: a
/// face reads wrong when its eyes dissolve into the skin. From Vision's face landmarks: each
/// eye's contour, smoothed into an almond, and its iris, a circle around the pupil sized from
/// the eye's width and clipped to the contour (the lids cover the rest of it).
///
/// Polygons are closed (the last point joins the first) and normalized to the photo (0...1,
/// origin top-left), contours first, then irises, each list ordered by position (top to
/// bottom, then left to right) and quantized to 1/4096 of the photo, so small differences in
/// Vision's output between runs don't reorder or jitter them.
nonisolated enum EyeFinder {
    /// Iris radius per eye width (corner to corner): an iris is about 11.7 mm across, an eye
    /// opening about 30 mm wide.
    static let irisRadiusPerEyeWidth = 0.2
    /// Eyes narrower than this share of the photo's long side are skipped: on a 1152-px canvas
    /// that is 14 px, too small to draw an outline and an iris inside it.
    static let minimumEyeWidth = 0.012
    /// An iris is drawn when at least this share of its circle shows between the lids.
    static let minimumVisibleIris = 0.15
    /// Faces Vision is less sure of than this are skipped.
    static let minimumFaceConfidence: Float = 0.5
    /// A face's eyes are outlined only when they look like that face's eyes, so landmarks that
    /// went wrong (the simulator returns two tiny overlapping eyes mid-face) never draw: every
    /// contour point inside the face box grown by `faceMargin` of its size on each side, each eye
    /// `eyeWidthPerFace` of the box's width (an eye opening is about a fifth of a face), centers
    /// `separationPerFace` of it apart (about two eye widths) and at least
    /// `minimumSeparationPerEyeWidth` eye widths apart (eyes don't overlap).
    static let faceMargin = 0.1
    static let eyeWidthPerFace: ClosedRange<Double> = 0.1...0.4
    static let separationPerFace: ClosedRange<Double> = 0.25...0.75
    static let minimumSeparationPerEyeWidth = 1.2
    /// Points per contour segment after smoothing, and per iris circle.
    static let contourSubdivisions = 4
    static let irisPoints = 32
    static let quantum = 4096.0

    /// The eyes of every face Vision finds in `image` (upright pixels). Empty when there are
    /// none or Vision can't run. The faces (`SubjectVision`'s findings) are handed to the landmarks
    /// request, the pipeline Vision documents for landmarks of known faces.
    static func eyes(in image: CGImage) async -> [[SIMD2<Float>]] {
        let faces = await SubjectVision.findings(in: image).faces.observations.filter { $0.confidence >= minimumFaceConfidence }
        guard !faces.isEmpty else { return [] }
        let handler = VNImageRequestHandler(cgImage: image, options: [:])
        let request = VNDetectFaceLandmarksRequest()
        request.constellation = .constellation76Points
        request.inputFaceObservations = faces
        do {
            try handler.perform([request])
        } catch {
            Log.create.error("Finding eyes failed: \(String(describing: error), privacy: .public)")
            return []
        }
        let size = CGSize(width: image.width, height: image.height)
        let longSide = Double(max(image.width, image.height))
        // Vision's image points and boxes have their origin at the bottom left.
        func flipped(_ p: CGPoint) -> SIMD2<Double> { SIMD2(Double(p.x), Double(size.height) - Double(p.y)) }
        var found: [Eye] = []
        for face in request.results ?? [] {
            guard let landmarks = face.landmarks else { continue }
            func eye(_ region: VNFaceLandmarkRegion2D?, _ pupil: VNFaceLandmarkRegion2D?) -> Eye? {
                guard let region else { return nil }
                let center = pupil?.pointsInImage(imageSize: size).first.map(flipped)
                return Eye(contour: region.pointsInImage(imageSize: size).map(flipped), pupil: center, longSide: longSide)
            }
            let box = face.boundingBox
            let faceBox = CGRect(
                x: box.minX * size.width, y: (1 - box.maxY) * size.height,
                width: box.width * size.width, height: box.height * size.height)
            guard let left = eye(landmarks.leftEye, landmarks.leftPupil), let right = eye(landmarks.rightEye, landmarks.rightPupil),
                  plausible(left, right, in: faceBox)
            else { continue }
            found += [left, right]
        }
        return polygons(of: found, width: Double(image.width), height: Double(image.height))
    }

    /// Whether two eyes look like the eyes of the face in `face` (photo pixels, origin top-left);
    /// see `faceMargin`.
    static func plausible(_ a: Eye, _ b: Eye, in face: CGRect) -> Bool {
        let faceWidth = Double(face.width)
        guard faceWidth > 0, face.height > 0 else { return false }
        let grown = face.insetBy(dx: -face.width * faceMargin, dy: -face.height * faceMargin)
        for point in a.contour + b.contour where !grown.contains(CGPoint(x: point.x, y: point.y)) { return false }
        guard eyeWidthPerFace.contains(a.width / faceWidth), eyeWidthPerFace.contains(b.width / faceWidth) else { return false }
        let separation = simd_distance(a.middle, b.middle)
        return separationPerFace.contains(separation / faceWidth)
            && separation >= minimumSeparationPerEyeWidth * max(a.width, b.width)
    }

    /// One eye in photo pixels (origin top-left).
    nonisolated struct Eye {
        var contour: [SIMD2<Double>]
        var iris: [SIMD2<Double>]?
        /// Corner to corner, and the mean of Vision's contour points.
        var width: Double
        var middle: SIMD2<Double>

        /// Nil when the contour is degenerate or the eye too small to outline.
        init?(contour points: [SIMD2<Double>], pupil: SIMD2<Double>?, longSide: Double) {
            guard points.count >= 3 else { return nil }
            var span = 0.0
            for a in points {
                for b in points { span = max(span, simd_distance(a, b)) }
            }
            guard span >= EyeFinder.minimumEyeWidth * longSide else { return nil }
            width = span
            contour = EyeFinder.smoothed(points)
            let mean: SIMD2<Double> = points.reduce(SIMD2<Double>.zero, +) / Double(points.count)
            middle = mean
            let center = pupil ?? mean
            let radius = EyeFinder.irisRadiusPerEyeWidth * span
            let circle = (0..<EyeFinder.irisPoints).map { i -> SIMD2<Double> in
                let angle = 2 * Double.pi * Double(i) / Double(EyeFinder.irisPoints)
                let direction = SIMD2<Double>(cos(angle), sin(angle))
                return center + radius * direction
            }
            let visible = EyeFinder.clip(circle, to: EyeFinder.convexHull(contour))
            let circleArea = Double.pi * radius * radius
            iris = visible.count >= 3 && abs(EyeFinder.area(visible)) >= EyeFinder.minimumVisibleIris * circleArea ? visible : nil
        }
    }

    /// Contours (ordered by position), then the irises of the same eyes in the same order,
    /// normalized and quantized.
    static func polygons(of eyes: [Eye], width: Double, height: Double) -> [[SIMD2<Float>]] {
        func centroid(_ points: [SIMD2<Double>]) -> SIMD2<Double> { points.reduce(SIMD2<Double>.zero, +) / Double(points.count) }
        let ordered = eyes.sorted {
            let a = centroid($0.contour), b = centroid($1.contour)
            return (a.y, a.x) < (b.y, b.x)
        }
        func normalized(_ points: [SIMD2<Double>]) -> [SIMD2<Float>] {
            points.map { p in
                let x = min(max((p.x / width * quantum).rounded() / quantum, 0), 1)
                let y = min(max((p.y / height * quantum).rounded() / quantum, 0), 1)
                return SIMD2(Float(x), Float(y))
            }
        }
        return ordered.map { normalized($0.contour) } + ordered.compactMap { $0.iris.map(normalized) }
    }

    /// A closed centripetal Catmull–Rom spline through `points` (no loops or overshoot at the
    /// eye's corners), `contourSubdivisions` points per segment.
    static func smoothed(_ points: [SIMD2<Double>]) -> [SIMD2<Double>] {
        let n = points.count
        var out: [SIMD2<Double>] = []
        out.reserveCapacity(n * contourSubdivisions)
        for i in 0..<n {
            let p0 = points[(i + n - 1) % n], p1 = points[i], p2 = points[(i + 1) % n], p3 = points[(i + 2) % n]
            // Knot spacing: the square root of each chord (centripetal); a tiny floor keeps
            // repeated points from dividing by zero.
            func knot(_ a: SIMD2<Double>, _ b: SIMD2<Double>) -> Double { max(simd_distance(a, b).squareRoot(), 1e-6) }
            let t0 = 0.0
            let t1 = t0 + knot(p0, p1)
            let t2 = t1 + knot(p1, p2)
            let t3 = t2 + knot(p2, p3)
            for k in 0..<contourSubdivisions {
                let t = t1 + (t2 - t1) * Double(k) / Double(contourSubdivisions)
                // Barry and Goldman's pyramid of linear blends.
                let a1 = blend(p0, p1, from: t0, to: t1, at: t)
                let a2 = blend(p1, p2, from: t1, to: t2, at: t)
                let a3 = blend(p2, p3, from: t2, to: t3, at: t)
                let b1 = blend(a1, a2, from: t0, to: t2, at: t)
                let b2 = blend(a2, a3, from: t1, to: t3, at: t)
                out.append(blend(b1, b2, from: t1, to: t2, at: t))
            }
        }
        return out
    }

    /// The point at parameter `t` on the line through `a` (at `ta`) and `b` (at `tb`).
    private static func blend(_ a: SIMD2<Double>, _ b: SIMD2<Double>, from ta: Double, to tb: Double, at t: Double) -> SIMD2<Double> {
        let wa: Double = (tb - t) / (tb - ta)
        let wb: Double = (t - ta) / (tb - ta)
        return wa * a + wb * b
    }

    /// Andrew's monotone chain; counter-clockwise in a y-up frame.
    static func convexHull(_ points: [SIMD2<Double>]) -> [SIMD2<Double>] {
        let sorted = points.sorted { ($0.x, $0.y) < ($1.x, $1.y) }
        guard sorted.count >= 3 else { return sorted }
        func cross(_ o: SIMD2<Double>, _ a: SIMD2<Double>, _ b: SIMD2<Double>) -> Double {
            (a.x - o.x) * (b.y - o.y) - (a.y - o.y) * (b.x - o.x)
        }
        var lower: [SIMD2<Double>] = [], upper: [SIMD2<Double>] = []
        for p in sorted {
            while lower.count >= 2 && cross(lower[lower.count - 2], lower[lower.count - 1], p) <= 0 { lower.removeLast() }
            lower.append(p)
        }
        for p in sorted.reversed() {
            while upper.count >= 2 && cross(upper[upper.count - 2], upper[upper.count - 1], p) <= 0 { upper.removeLast() }
            upper.append(p)
        }
        return Array(lower.dropLast() + upper.dropLast())
    }

    /// Sutherland–Hodgman: the part of `subject` inside the convex polygon `clip`.
    static func clip(_ subject: [SIMD2<Double>], to clip: [SIMD2<Double>]) -> [SIMD2<Double>] {
        guard clip.count >= 3 else { return [] }
        let orientation: Double = area(clip) >= 0 ? 1 : -1
        func side(_ a: SIMD2<Double>, _ b: SIMD2<Double>, _ p: SIMD2<Double>) -> Double {
            orientation * ((b.x - a.x) * (p.y - a.y) - (b.y - a.y) * (p.x - a.x))
        }
        var output = subject
        for i in 0..<clip.count where !output.isEmpty {
            let a = clip[i], b = clip[(i + 1) % clip.count]
            let input = output
            output = []
            for j in 0..<input.count {
                let p = input[j], q = input[(j + 1) % input.count]
                let sp = side(a, b, p), sq = side(a, b, q)
                if sp >= 0 { output.append(p) }
                if (sp >= 0) != (sq >= 0) {
                    let along: Double = sp / (sp - sq)
                    output.append(p + (q - p) * along)
                }
            }
        }
        return output
    }

    /// Signed area (shoelace).
    static func area(_ polygon: [SIMD2<Double>]) -> Double {
        var sum = 0.0
        for i in 0..<polygon.count {
            let a = polygon[i], b = polygon[(i + 1) % polygon.count]
            sum += a.x * b.y - b.x * a.y
        }
        return sum / 2
    }
}
