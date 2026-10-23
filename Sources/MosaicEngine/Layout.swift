#if canImport(Darwin)
import Darwin
#else
import Glibc
#endif

nonisolated extension MosaicEngine {
    /// The prototype's tile laying: a canvas (the working image, twice the photo), the local pitch,
    /// and the forbidden map that keeps each new tile a joint away from those already laid.
    nonisolated final class Layout {
        enum Eye: Sendable { case iris, pupil }

        struct Piece {
            /// Corners in working pixels.
            var poly: [SIMD2<Double>]
            var strand: Bool
            var eye: Eye?
            var feature: String?
        }

        let width: Int, height: Int
        /// The joint, in working pixels.
        let grout: Int
        /// The tile pitch at each working pixel.
        let pitchMap: [Float]
        /// Nonzero where no new tile may go: laid tiles, dilated by the joint.
        var forbid: [UInt8]
        var pieces: [Piece] = []
        private let ellipse: [Int]

        init(width: Int, height: Int, grout: Int, pitchMap: [Float]) {
            self.width = width; self.height = height; self.grout = grout; self.pitchMap = pitchMap
            forbid = [UInt8](repeating: 0, count: width * height)
            ellipse = Morph.ellipseRows(radius: grout)
        }

        /// Inside the frame a joint wide round the picture's edge.
        @inline(__always) func inside(_ x: Int, _ y: Int) -> Bool {
            x >= grout && x < width - grout && y >= grout && y < height - grout
        }

        /// The pitch at a point (the pixel it falls in, clamped to the canvas).
        func pitch(_ c: SIMD2<Double>) -> Double {
            func cell(_ v: Double, _ n: Int) -> Int {
                guard v.isFinite else { return 0 }
                return clampIndex(Int(Swift.max(Swift.min(v, 1e9), -1e9)), n)
            }
            return Double(pitchMap[cell(c.y, height) * width + cell(c.x, width)])
        }

        /// A square tile at `c` turned along `t`, its side the local pitch less the joint (times `grow`).
        func square(_ c: SIMD2<Double>, _ t: SIMD2<Double>, grow: Double = 1) -> [SIMD2<Double>] {
            let h = grow * (pitch(c) - Double(grout)) / 2
            let tn = t / ((t.x * t.x + t.y * t.y).squareRoot() + 1e-9)
            let n = SIMD2(-tn.y, tn.x)
            return [(-1.0, -1.0), (1, -1), (1, 1), (-1, 1)].map { c + $0.0 * h * tn + $0.1 * h * n }
        }

        /// A point every local pitch along a polyline, the first half a pitch in; and its length.
        func resample(_ P: [SIMD2<Double>]) -> (points: [SIMD2<Double>], length: Double) {
            guard let first = P.first else { return ([], 0) }
            var d = [0.0]
            d.reserveCapacity(P.count)
            for i in 1..<Swift.max(P.count, 1) {
                let v = P[i] - P[i - 1]
                d.append(d[i - 1] + (v.x * v.x + v.y * v.y).squareRoot())
            }
            let length = d[d.count - 1]
            guard length >= 1 else { return ([first], length) }
            var j = 0
            func at(_ x: Double) -> SIMD2<Double> {
                while j + 1 < d.count && d[j + 1] <= x { j += 1 }
                guard j + 1 < d.count else { return P[P.count - 1] }
                let t = (x - d[j]) / (d[j + 1] - d[j])
                return P[j] + (P[j + 1] - P[j]) * t
            }
            var out: [SIMD2<Double>] = []
            var x = pitch(first) / 2
            while x < length {
                let c = at(x)
                out.append(c)
                x += Swift.max(pitch(c), 1)
            }
            return (out, length)
        }

        /// The prototype's `place`: the polygon rasterised, less what is forbidden and outside the
        /// frame; its biggest piece kept if big enough (`minFrac` of a whole tile), outlined and
        /// simplified, then forbidden to later tiles with the joint round it.
        @discardableResult
        func place(_ poly: [SIMD2<Double>], strand: Bool, minFrac: Double, eye: Eye? = nil, feature: String? = nil) -> Bool {
            guard poly.count >= 3 else { return false }
            var lo = poly[0], hi = poly[0]
            for p in poly { lo = pointwiseMin(lo, p); hi = pointwiseMax(hi, p) }
            guard lo.x.isFinite, lo.y.isFinite, hi.x.isFinite, hi.y.isFinite,
                  hi.x - lo.x < Double(width), hi.y - lo.y < Double(height),
                  hi.x > -2, hi.y > -2, lo.x < Double(width + 2), lo.y < Double(height + 2) else { return false }
            let x0 = Swift.max(Int(lo.x) - 2, 0), y0 = Swift.max(Int(lo.y) - 2, 0)
            let x1 = Swift.min(Int(hi.x) + 3, width), y1 = Swift.min(Int(hi.y) + 3, height)
            guard x1 > x0, y1 > y0 else { return false }
            let bw = x1 - x0, bh = y1 - y0
            var m = [UInt8](repeating: 0, count: bw * bh)
            Polygon.fill(poly, origin: SIMD2(Double(x0), Double(y0)), quarter: true, into: &m, width: bw, height: bh)
            var count = 0
            forbid.withUnsafeBufferPointer { f in
                for yy in 0..<bh {
                    let y = y0 + yy
                    for xx in 0..<bw where m[yy * bw + xx] != 0 {
                        let x = x0 + xx
                        if !inside(x, y) || f[y * width + x] != 0 { m[yy * bw + xx] = 0 } else { count += 1 }
                    }
                }
            }
            let side = pitch(Polygon.mean(poly)) - Double(grout)
            let need = minFrac * side * side
            guard Double(count) >= need, count > 0 else { return false }
            let (labels, sizes) = Components.label(m, width: bw, height: bh)
            guard sizes.count >= 2 else { return false }
            var k = 1
            for j in 2..<sizes.count where sizes[j] > sizes[k] { k = j }
            guard Double(sizes[k]) >= need else { return false }
            if sizes.count > 2 { for i in m.indices { m[i] = labels[i] == Int32(k) ? 1 : 0 } }
            var tracer = BorderTracer(m, width: bw, height: bh)
            let outline = tracer.first().map { SIMD2(Double($0.x) + Double(x0), Double($0.y) + Double(y0)) }
            let p = Polygon.simplify(closed: outline, epsilon: 1.4)
            guard p.count >= 3 else { return false }
            stamp(p)
            pieces.append(Piece(poly: p, strand: strand, eye: eye, feature: feature))
            return true
        }

        /// Forbids a laid tile (whole-pixel corners) and the joint round it: its fill dilated by the
        /// elliptical (2·grout+1)² kernel.
        private func stamp(_ p: [SIMD2<Double>]) {
            var lo = p[0], hi = p[0]
            for q in p { lo = pointwiseMin(lo, q); hi = pointwiseMax(hi, q) }
            let ox = Int(lo.x.rounded(.down)) - grout - 1, oy = Int(lo.y.rounded(.down)) - grout - 1
            let bw = Int(hi.x.rounded(.up)) - ox + grout + 2, bh = Int(hi.y.rounded(.up)) - oy + grout + 2
            var q = [UInt8](repeating: 0, count: bw * bh)
            Polygon.fill(p, origin: SIMD2(Double(ox), Double(oy)), quarter: false, into: &q, width: bw, height: bh)
            let w = width, h = height, g = grout
            forbid.withUnsafeMutableBufferPointer { f in
                for yy in 0..<bh {
                    var xx = 0
                    while xx < bw {
                        guard q[yy * bw + xx] != 0 else { xx += 1; continue }
                        let a = xx
                        while xx < bw && q[yy * bw + xx] != 0 { xx += 1 }
                        let b = xx - 1
                        for (i, half) in ellipse.enumerated() {
                            let y = oy + yy + i - g
                            guard y >= 0 && y < h else { continue }
                            let xa = Swift.max(ox + a - half, 0), xb = Swift.min(ox + b + half, w - 1)
                            if xa <= xb { for x in xa...xb { f[y * w + x] = 1 } }
                        }
                    }
                }
            }
        }
    }

    /// The part of `poly` inside `ring` (its biggest piece), traced from a raster four times finer
    /// than the canvas; nil when they don't meet.
    static func intersect(_ poly: [SIMD2<Double>], _ ring: [SIMD2<Double>]) -> [SIMD2<Double>]? {
        guard poly.count >= 3, ring.count >= 3 else { return nil }
        let f = 4.0
        var lo = poly[0], hi = poly[0]
        for p in poly { lo = pointwiseMin(lo, p); hi = pointwiseMax(hi, p) }
        lo -= 1; hi += 1
        let gw = Int(((hi.x - lo.x) * f).rounded(.up)) + 1, gh = Int(((hi.y - lo.y) * f).rounded(.up)) + 1
        guard gw > 0, gh > 0, gw * gh < 16_000_000 else { return nil }
        var a = [UInt8](repeating: 0, count: gw * gh), b = a
        Polygon.fill(poly.map { ($0 - lo) * f }, quarter: false, into: &a, width: gw, height: gh)
        Polygon.fill(ring.map { ($0 - lo) * f }, quarter: false, into: &b, width: gw, height: gh)
        for i in a.indices { a[i] &= b[i] }
        let (labels, sizes) = Components.label(a, width: gw, height: gh)
        guard sizes.count >= 2 else { return nil }
        var k = 1
        for j in 2..<sizes.count where sizes[j] > sizes[k] { k = j }
        for i in a.indices { a[i] = labels[i] == Int32(k) ? 1 : 0 }
        var tracer = BorderTracer(a, width: gw, height: gh)
        let outline = tracer.first().map { lo + SIMD2(Double($0.x), Double($0.y)) / f }
        let p = Polygon.simplify(closed: outline, epsilon: 0.3)
        return p.count >= 3 ? p : nil
    }
}
