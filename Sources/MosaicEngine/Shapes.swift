nonisolated extension MosaicEngine {
    // Polygons and the borders of masks: OpenCV's fillPoly, findContours, approxPolyDP and
    // pointPolygonTest as the prototype used them, in plain Swift.

    nonisolated enum Polygon {
        /// `cv2.fillPoly`: fills `poly` (its coordinates less `origin`) into a `width × height` mask.
        /// Pixel centres sit at whole coordinates; the outline is drawn too, so the fill is inclusive.
        /// `quarter` keeps vertices at quarter-pixel precision as `shift=2` does (rows rounded to whole
        /// pixels, as OpenCV does); otherwise they're rounded to whole pixels.
        static func fill(_ poly: [SIMD2<Double>], origin: SIMD2<Double> = .zero, quarter: Bool,
                         into m: inout [UInt8], width w: Int, height h: Int, value: UInt8 = 1) {
            let n = poly.count
            guard n > 0, w > 0, h > 0 else { return }
            var fx = [Double](repeating: 0, count: n), ry = [Int](repeating: 0, count: n), rx = [Int](repeating: 0, count: n)
            for i in 0..<n {
                let q = poly[i] - origin
                guard q.x.isFinite, q.y.isFinite, abs(q.x) < 1e7, abs(q.y) < 1e7 else { return }
                if quarter {
                    let X = Int((q.x * 4).rounded(.toNearestOrEven)), Y = Int((q.y * 4).rounded(.toNearestOrEven))
                    fx[i] = Double(X) / 4; ry[i] = (Y + 2) >> 2; rx[i] = (X + 2) >> 2
                } else {
                    let X = Int(q.x.rounded(.toNearestOrEven)), Y = Int(q.y.rounded(.toNearestOrEven))
                    fx[i] = Double(X); ry[i] = Y; rx[i] = X
                }
            }
            m.withUnsafeMutableBufferPointer { mm in
                // The outline, as OpenCV draws it under the fill: 8-connected lines between rounded vertices.
                var j = n - 1
                for i in 0..<n {
                    line(rx[j], ry[j], rx[i], ry[i], mm, w, h, value)
                    j = i
                }
                // The inside: each row's spans between edge crossings, from ceil(left) to floor(right).
                var lo = Int.max, hi = Int.min
                for y in ry { lo = Swift.min(lo, y); hi = Swift.max(hi, y) }
                lo = Swift.max(lo, 0); hi = Swift.min(hi, h)
                guard lo < hi else { return }
                var xs = [Double]()
                xs.reserveCapacity(8)
                for y in lo..<hi {
                    xs.removeAll(keepingCapacity: true)
                    var a = n - 1
                    for b in 0..<n {
                        let ya = ry[a], yb = ry[b]
                        if ya != yb {
                            let (y0, y1, x0, x1) = ya < yb ? (ya, yb, fx[a], fx[b]) : (yb, ya, fx[b], fx[a])
                            if y >= y0 && y < y1 { xs.append(x0 + Double(y - y0) * (x1 - x0) / Double(y1 - y0)) }
                        }
                        a = b
                    }
                    guard xs.count >= 2 else { continue }
                    xs.sort()
                    var k = 0
                    while k + 1 < xs.count {
                        let x0 = Swift.max(Int((xs[k] - 1e-9).rounded(.up)), 0)
                        let x1 = Swift.min(Int((xs[k + 1] + 1e-9).rounded(.down)), w - 1)
                        if x0 <= x1 { for x in x0...x1 { mm[y * w + x] = value } }
                        k += 2
                    }
                }
            }
        }

        /// An 8-connected Bresenham line, both ends included, clipped to the mask.
        static func line(_ x0: Int, _ y0: Int, _ x1: Int, _ y1: Int, _ m: UnsafeMutableBufferPointer<UInt8>,
                         _ w: Int, _ h: Int, _ value: UInt8) {
            let dx = abs(x1 - x0), dy = -abs(y1 - y0)
            let sx = x0 < x1 ? 1 : -1, sy = y0 < y1 ? 1 : -1
            var err = dx + dy, x = x0, y = y0
            while true {
                if x >= 0 && x < w && y >= 0 && y < h { m[y * w + x] = value }
                if x == x1 && y == y1 { break }
                let e2 = 2 * err
                if e2 >= dy { err += dy; x += sx }
                if e2 <= dx { err += dx; y += sy }
            }
        }

        /// `cv2.pointPolygonTest(…) >= 0`: inside or on the outline.
        static func contains(_ poly: [SIMD2<Double>], _ p: SIMD2<Double>) -> Bool {
            let n = poly.count
            guard n > 2 else { return false }
            var inside = false
            var j = n - 1
            for i in 0..<n {
                let a = poly[i], b = poly[j]
                // On the edge?
                let ab = b - a, ap = p - a
                let len2 = ab.x * ab.x + ab.y * ab.y
                if len2 == 0 {
                    if ap == .zero { return true }   // a repeated corner is no edge
                } else if abs(ab.x * ap.y - ab.y * ap.x) <= 1e-9 * len2.squareRoot() {
                    let t = ap.x * ab.x + ap.y * ab.y
                    if t >= 0 && t <= len2 { return true }
                }
                if (a.y > p.y) != (b.y > p.y), p.x < (b.x - a.x) * (p.y - a.y) / (b.y - a.y) + a.x { inside.toggle() }
                j = i
            }
            return inside
        }

        /// The shoelace area (absolute).
        static func area(_ poly: [SIMD2<Double>]) -> Double {
            guard poly.count > 2 else { return 0 }
            var s = 0.0, j = poly.count - 1
            for i in poly.indices { s += poly[j].x * poly[i].y - poly[i].x * poly[j].y; j = i }
            return abs(s) / 2
        }

        static func mean(_ poly: [SIMD2<Double>]) -> SIMD2<Double> {
            guard !poly.isEmpty else { return .zero }
            return poly.reduce(.zero, +) / Double(poly.count)
        }

        /// `cv2.approxPolyDP(contour, ε, closed=True)`: Douglas–Peucker on a ring split at two far-apart
        /// points, then OpenCV's pass that drops vertices lying on the line through their neighbours.
        static func simplify(closed pts: [SIMD2<Double>], epsilon: Double) -> [SIMD2<Double>] {
            let n = pts.count
            guard n > 2 else { return pts }
            // OpenCV's three passes, each from the last one's farthest point (the first found, going
            // round from it): the ring starts at the second pass's point and splits at the third's.
            func farthest(from i: Int) -> (Int, Double) {
                var best = i, bd = 0.0
                for j in 1..<n {
                    let k = (i + j) % n, d = pts[k] - pts[i], dd = d.x * d.x + d.y * d.y
                    if dd > bd { bd = dd; best = k }
                }
                return (best, bd)
            }
            let (first0, _) = farthest(from: 0)
            let (a, _) = farthest(from: first0)
            let (b, dab) = farthest(from: a)
            guard dab > epsilon * epsilon else { return [pts[a]] }
            func chain(_ from: Int, _ to: Int) -> [Int] {
                var out = [from], i = from
                while i != to { i = (i + 1) % n; out.append(i) }
                return out
            }
            let first = douglasPeucker(chain(a, b).map { pts[$0] }, epsilon: epsilon)
            let second = douglasPeucker(chain(b, a).map { pts[$0] }, epsilon: epsilon)
            var out = Array(first.dropLast()) + Array(second.dropLast())
            // Drop a vertex close to the line through its neighbours (OpenCV's last pass).
            let e2 = epsilon * epsilon
            var i = 0
            while i < out.count && out.count > 2 {
                let start = out[(i + out.count - 1) % out.count], p = out[i], end = out[(i + 1) % out.count]
                let dx = end.x - start.x, dy = end.y - start.y
                let dist = abs((p.x - start.x) * dy - (p.y - start.y) * dx)
                let inner = (p.x - start.x) * (end.x - p.x) + (p.y - start.y) * (end.y - p.y)
                if dist * dist <= 0.5 * e2 * (dx * dx + dy * dy) && dx != 0 && dy != 0 && inner >= 0 {
                    out.remove(at: i)
                } else {
                    i += 1
                }
            }
            return out
        }

        /// Douglas–Peucker on an open chain, both ends kept.
        static func douglasPeucker(_ pts: [SIMD2<Double>], epsilon: Double) -> [SIMD2<Double>] {
            let n = pts.count
            guard n > 2 else { return pts }
            var keep = [Bool](repeating: false, count: n)
            keep[0] = true; keep[n - 1] = true
            var stack = [(0, n - 1)]
            while let (lo, hi) = stack.popLast() {
                guard hi - lo > 1 else { continue }
                let a = pts[lo], b = pts[hi], d = b - a
                let len2 = d.x * d.x + d.y * d.y
                var best = -1, bd = -1.0
                for i in (lo + 1)..<hi {
                    let p = pts[i] - a
                    let dist2 = len2 > 0 ? pow2(p.x * d.y - p.y * d.x) / len2 : p.x * p.x + p.y * p.y
                    if dist2 > bd { bd = dist2; best = i }
                }
                if bd > epsilon * epsilon {
                    keep[best] = true
                    stack.append((best, hi)); stack.append((lo, best))
                }
            }
            return (0..<n).filter { keep[$0] }.map { pts[$0] }
        }
    }

    @inline(__always) static func pow2(_ x: Double) -> Double { x * x }

    /// Borders of binary masks by Suzuki and Abe's border following (1985), as `cv2.findContours`
    /// with `CHAIN_APPROX_NONE` walks them: every border pixel, in order, the image framed by zeros.
    nonisolated struct BorderTracer {
        let width: Int, height: Int
        private let stride: Int
        private var img: [Int32]
        private let deltas: [Int]

        /// `mask` nonzero is foreground.
        init(_ mask: UnsafeBufferPointer<UInt8>, width w: Int, height h: Int) {
            width = w; height = h; stride = w + 2
            var img = [Int32](repeating: 0, count: (w + 2) * (h + 2))
            for y in 0..<h {
                let row = (y + 1) * (w + 2) + 1
                for x in 0..<w where mask[y * w + x] != 0 { img[row + x] = 1 }
            }
            self.img = img
            let s = w + 2
            // E, NE, N, NW, W, SW, S, SE (counter-clockwise on screen), twice over.
            let d = [1, -s + 1, -s, -s - 1, -1, s - 1, s, s + 1]
            deltas = d + d
        }

        init(_ mask: [UInt8], width w: Int, height h: Int) {
            self = mask.withUnsafeBufferPointer { BorderTracer($0, width: w, height: h) }
        }

        /// Every border, outer and hole alike (`RETR_LIST`), in the order the raster scan finds them.
        mutating func all() -> [[SIMD2<Int32>]] {
            var out: [[SIMD2<Int32>]] = []
            var nbd: Int32 = 1
            let s = stride, w = width, h = height
            guard w > 0, h > 0 else { return out }
            img.withUnsafeMutableBufferPointer { im in
                deltas.withUnsafeBufferPointer { dl in
                    for y in 1...h {
                        var prev: Int32 = 0
                        for x in 1...w {
                            let i = y * s + x
                            let p = im[i]
                            if p != prev {
                                if prev == 0 && p == 1 {
                                    nbd += 1
                                    out.append(Self.follow(im, dl, s, start: i, hole: false, nbd: nbd))
                                } else if p == 0 && prev >= 1 {
                                    nbd += 1
                                    out.append(Self.follow(im, dl, s, start: i - 1, hole: true, nbd: nbd))
                                }
                            }
                            prev = im[i]
                        }
                    }
                }
            }
            return out
        }

        /// The outer border of the first foreground component in raster order (`RETR_EXTERNAL` for a
        /// mask holding one component), or nothing for an empty mask.
        mutating func first() -> [SIMD2<Int32>] {
            let s = stride, w = width, h = height
            return img.withUnsafeMutableBufferPointer { im in
                deltas.withUnsafeBufferPointer { dl in
                    for y in 1..<(h + 1) {
                        for x in 1..<(w + 1) where im[y * s + x] == 1 {
                            return Self.follow(im, dl, s, start: y * s + x, hole: false, nbd: 2)
                        }
                    }
                    return []
                }
            }
        }

        private static func follow(_ im: UnsafeMutableBufferPointer<Int32>, _ dl: UnsafeBufferPointer<Int>, _ stride: Int,
                                   start i0: Int, hole: Bool, nbd: Int32) -> [SIMD2<Int32>] {
            @inline(__always) func point(_ i: Int) -> SIMD2<Int32> { SIMD2(Int32(i % stride - 1), Int32(i / stride - 1)) }
            let s0 = hole ? 0 : 4
            var s = s0, i1 = i0
            repeat {
                s = (s - 1) & 7
                i1 = i0 + dl[s]
            } while im[i1] == 0 && s != s0
            if s == s0 {
                im[i0] = -nbd
                return [point(i0)]
            }
            var pts: [SIMD2<Int32>] = []
            var i3 = i0
            while true {
                let sEnd = s
                var i4 = i3
                repeat {
                    s += 1
                    i4 = i3 + dl[s]
                } while im[i4] == 0
                s &= 7
                if UInt(bitPattern: s - 1) < UInt(sEnd) {
                    im[i3] = -nbd
                } else if im[i3] == 1 {
                    im[i3] = nbd
                }
                pts.append(point(i3))
                if i4 == i0 && i3 == i1 { break }
                i3 = i4
                s = (s + 4) & 7
            }
            return pts
        }
    }
}
